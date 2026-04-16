#!/usr/bin/env python3
"""Build and deploy Flutter Web to HostGator via FTPS.

This script reproduces the deploy steps from `.github/workflows/deploy-web.yml`:
1) flutter pub get
2) flutter build web --release --no-wasm-dry-run --base-href <value>
3) generate build/web/.htaccess for SPA routing
4) delete all existing content from the remote target directory
5) upload build/web over FTPS, excluding *.map and canvaskit/**
6) persist a local state file with the latest hashes (informational)
"""

from __future__ import annotations

import argparse
import ftplib
import hashlib
import json
import os
import posixpath
import shutil
import socket
import ssl
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, Iterable, List, Set, Tuple


REQUIRED_SECRETS = ("WEB_FTP_SERVER", "WEB_FTP_USERNAME", "WEB_FTP_PASSWORD")
DEFAULT_STATE_FILE = ".ftp-deploy-sync-state-web.json"
FTP_RETRY_ERRORS = ftplib.all_errors + (socket.timeout, TimeoutError, EOFError, OSError)
ENV_FILE_BY_DEPLOY_ENV = {
    "dev": "secrets-dev.env",
    "prod": "secrets-prod.env",
}


@dataclass(frozen=True)
class DeployTarget:
    local_path: Path
    relative_posix: str


class TolerantFTP_TLS(ftplib.FTP_TLS):
    """FTP_TLS variant that tolerates SSL EOF on data-connection unwrap.

    Some FTP servers (including shared host setups) close TLS data sockets
    without a proper TLS close_notify, which raises SSLEOFError on unwrap.
    """

    def storbinary(self, cmd, fp, blocksize=8192, callback=None, rest=None):
        self.voidcmd("TYPE I")
        with self.transfercmd(cmd, rest) as conn:
            while True:
                buf = fp.read(blocksize)
                if not buf:
                    break
                conn.sendall(buf)
                if callback:
                    callback(buf)
            if isinstance(conn, ssl.SSLSocket):
                try:
                    conn.unwrap()
                except ssl.SSLEOFError:
                    # Upload usually succeeded; server closed abruptly.
                    pass
        return self.voidresp()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Build and deploy Flutter Web to HostGator.")
    parser.add_argument(
        "--deploy-env",
        default=None,
        help="Ambiente de deploy: dev ou prod. Quando omitido, solicita interativamente.",
    )
    parser.add_argument(
        "--base-href",
        default="/",
        help="Flutter web base href (ex: / or /subpasta/). Default: /",
    )
    parser.add_argument(
        "--repo-root",
        type=Path,
        default=None,
        help="Repository root path. Auto-detected when omitted.",
    )
    parser.add_argument(
        "--env-file",
        type=Path,
        default=None,
        help="Path para arquivo de secrets (sobrescreve --deploy-env quando informado).",
    )
    parser.add_argument(
        "--build-dir",
        type=Path,
        default=Path("build/web"),
        help="Flutter web build directory relative to repo root. Default: build/web",
    )
    parser.add_argument(
        "--state-file",
        type=Path,
        default=Path(DEFAULT_STATE_FILE),
        help=f"State file relative to repo root. Default: {DEFAULT_STATE_FILE}",
    )
    parser.add_argument(
        "--server-dir",
        default="/",
        help="FTP destination directory. Default: /",
    )
    parser.add_argument(
        "--build-only",
        action="store_true",
        help="Only run build steps and skip FTP upload.",
    )
    parser.add_argument(
        "--timeout",
        type=int,
        default=180,
        help="FTP timeout in seconds. Default: 180",
    )
    return parser.parse_args()


def log(message: str) -> None:
    print(f"[deploy-web] {message}")


def fail(message: str, exit_code: int = 1) -> None:
    print(f"[deploy-web] ERROR: {message}", file=sys.stderr)
    raise SystemExit(exit_code)


def find_repo_root(start: Path) -> Path:
    workflow_markers = (
        ".github/workflows/deploy-web.yml",
        ".github/workflows/web-deploy.yml",
        ".github/workflows/web-deploy-hostgator.yml",
    )
    for current in [start, *start.parents]:
        if (current / "pubspec.yaml").exists() and any((current / marker).exists() for marker in workflow_markers):
            return current
    fail("Nao foi possivel detectar o repo root automaticamente. Use --repo-root.")
    raise AssertionError("unreachable")


def run_command(command: List[str], cwd: Path) -> None:
    executable = shutil.which(command[0])
    if executable is None and os.name == "nt":
        executable = shutil.which(f"{command[0]}.bat") or shutil.which(f"{command[0]}.exe")
    if executable is None:
        fail(f"Executavel nao encontrado no PATH: {command[0]}")

    resolved_command = [executable, *command[1:]]
    printable = " ".join(resolved_command)
    log(f"Executando: {printable}")
    subprocess.run(resolved_command, cwd=cwd, check=True)


def normalize_rewrite_base(base_href: str) -> str:
    base = (base_href or "/").strip()
    if not base.startswith("/"):
        base = "/" + base
    if not base.endswith("/"):
        base += "/"
    return base


def generate_htaccess(build_dir: Path, base_href: str) -> None:
    rewrite_base = normalize_rewrite_base(base_href)
    content = (
        "<IfModule mod_rewrite.c>\n"
        "  RewriteEngine On\n"
        f"  RewriteBase {rewrite_base}\n"
        "  RewriteRule ^index\\.html$ - [L]\n"
        "  RewriteCond %{REQUEST_FILENAME} !-f\n"
        "  RewriteCond %{REQUEST_FILENAME} !-d\n"
        f"  RewriteRule . {rewrite_base}index.html [L]\n"
        "</IfModule>\n"
    )
    htaccess_path = build_dir / ".htaccess"
    htaccess_path.write_text(content, encoding="utf-8")
    log(f"Arquivo {htaccess_path} gerado com sucesso.")


def load_env_file(env_file: Path) -> Dict[str, str]:
    data: Dict[str, str] = {}
    if not env_file.exists():
        fail(f"Arquivo de secrets nao encontrado: {env_file}")

    for raw_line in env_file.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip().strip("'").strip('"')
        data[key] = value
    return data


def _map_deploy_env(raw_value: str) -> str:
    value = (raw_value or "").strip().lower()
    aliases = {
        "dev": "dev",
        "development": "dev",
        "develop": "dev",
        "prod": "prod",
        "production": "prod",
        "prd": "prod",
    }
    return aliases.get(value, "")


def normalize_deploy_env(raw_value: str) -> str:
    normalized = _map_deploy_env(raw_value)
    if not normalized:
        fail(f"Ambiente de deploy invalido: {raw_value}. Use dev ou prod.")
    return normalized


def resolve_deploy_env(user_deploy_env: str | None) -> str:
    if user_deploy_env:
        return normalize_deploy_env(user_deploy_env)

    if not sys.stdin.isatty():
        fail("Ambiente de deploy nao informado. Use --deploy-env dev|prod.")

    while True:
        try:
            chosen = input("Tipo de deploy (dev/prod): ").strip()
        except EOFError:
            fail("Ambiente de deploy nao informado. Use --deploy-env dev|prod.")

        if not chosen:
            log("Informe dev ou prod.")
            continue
        mapped = _map_deploy_env(chosen)
        if mapped:
            return mapped
        log("Valor invalido. Informe dev ou prod.")


def resolve_env_file(
    repo_root: Path,
    script_dir: Path,
    user_env_file: Path | None,
    deploy_env: str,
) -> Path:
    if user_env_file is not None:
        return (repo_root / user_env_file).resolve() if not user_env_file.is_absolute() else user_env_file.resolve()

    env_filename = ENV_FILE_BY_DEPLOY_ENV.get(deploy_env)
    if not env_filename:
        fail(f"Deploy env sem mapeamento de arquivo: {deploy_env}")

    candidates = [
        script_dir / env_filename,
        repo_root / "deploy" / "workflow-hostgator" / env_filename,
        repo_root / "scripts" / "workflow-hostgator" / env_filename,
        repo_root / "scritps" / "workflow-hostgator" / env_filename,
    ]
    for candidate in candidates:
        if candidate.exists():
            return candidate.resolve()
    fail(f"Nao encontrei {env_filename}. Passe --env-file com o caminho correto.")
    raise AssertionError("unreachable")


def validate_required_secrets(config: Dict[str, str]) -> None:
    missing = [name for name in REQUIRED_SECRETS if not config.get(name)]
    if missing:
        fail(f"Secrets ausentes: {', '.join(missing)}")


def sha1_file(path: Path) -> str:
    digest = hashlib.sha1()
    with path.open("rb") as file_obj:
        for chunk in iter(lambda: file_obj.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def should_exclude(relative_posix: str) -> bool:
    if relative_posix.endswith(".map"):
        return True
    if relative_posix.startswith("canvaskit/"):
        return True
    return False


def collect_deploy_targets(build_dir: Path) -> List[DeployTarget]:
    targets: List[DeployTarget] = []
    for path in sorted(build_dir.rglob("*")):
        if not path.is_file():
            continue
        relative_posix = path.relative_to(build_dir).as_posix()
        if should_exclude(relative_posix):
            continue
        targets.append(DeployTarget(local_path=path, relative_posix=relative_posix))
    return targets


def load_state(path: Path) -> Dict[str, Dict[str, str]]:
    if not path.exists():
        return {}
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError):
        log(f"State file invalido ({path}), iniciando sincronizacao completa.")
        return {}
    files = payload.get("files", {})
    if not isinstance(files, dict):
        return {}
    normalized: Dict[str, Dict[str, str]] = {}
    for key, value in files.items():
        if isinstance(key, str) and isinstance(value, dict):
            normalized[key] = value
    return normalized


def save_state(path: Path, files: Dict[str, Dict[str, str]]) -> None:
    payload = {"version": 1, "files": files}
    path.write_text(json.dumps(payload, indent=2, sort_keys=True), encoding="utf-8")


def remote_join(server_dir: str, relative_posix: str) -> str:
    base = server_dir.strip() or "/"
    if not base.startswith("/"):
        base = "/" + base
    base = base.rstrip("/")
    if not base:
        base = "/"
    rel = relative_posix.lstrip("/")
    return f"/{rel}" if base == "/" else f"{base}/{rel}"


def normalize_remote_dir(server_dir: str) -> str:
    base = (server_dir or "/").strip()
    if not base.startswith("/"):
        base = "/" + base
    base = base.rstrip("/")
    return base or "/"


def ensure_remote_dirs(ftp: ftplib.FTP_TLS, remote_file: str, cache: Set[str]) -> None:
    parent = posixpath.dirname(remote_file)
    if not parent or parent in (".", "/"):
        return
    segments = [segment for segment in parent.split("/") if segment]
    current = ""
    for segment in segments:
        current = f"{current}/{segment}"
        if current in cache:
            continue
        try:
            ftp.mkd(current)
        except ftplib.error_perm as exc:
            # 550 usually means directory already exists.
            if "550" not in str(exc):
                raise
        cache.add(current)


def remove_remote_file(ftp: ftplib.FTP_TLS, remote_file: str) -> bool:
    try:
        ftp.delete(remote_file)
        return True
    except ftplib.error_perm as exc:
        # 550 typically means missing file/permission.
        log(f"Aviso ao deletar {remote_file}: {exc}")
        return False


def _list_remote_children_mlsd(ftp: ftplib.FTP_TLS, remote_dir: str) -> Tuple[List[str], List[str]]:
    files: List[str] = []
    dirs: List[str] = []
    start_pwd = ftp.pwd()
    try:
        ftp.cwd(remote_dir)
        for name, facts in ftp.mlsd():
            if name in (".", ".."):
                continue
            entry = f"/{name}" if remote_dir == "/" else f"{remote_dir.rstrip('/')}/{name}"
            entry_type = (facts or {}).get("type", "").lower()
            if entry_type == "dir":
                dirs.append(entry)
            elif entry_type == "file":
                files.append(entry)
    finally:
        try:
            ftp.cwd(start_pwd)
        except ftplib.error_perm:
            pass
    return files, dirs


def _list_remote_children_nlst(ftp: ftplib.FTP_TLS, remote_dir: str) -> Tuple[List[str], List[str]]:
    files: List[str] = []
    dirs: List[str] = []

    start_pwd = ftp.pwd()
    try:
        ftp.cwd(remote_dir)
        raw_entries = ftp.nlst()
    except ftplib.error_perm as exc:
        message = str(exc)
        if "550" in message:
            return files, dirs
        raise
    finally:
        try:
            ftp.cwd(remote_dir)
        except ftplib.error_perm:
            pass

    for raw_entry in raw_entries:
        if not raw_entry:
            continue
        entry = raw_entry.strip()
        if not entry:
            continue

        # Some servers include the queried directory itself in NLST output.
        normalized_remote_dir = remote_dir.rstrip("/") or "/"
        normalized_entry = entry.rstrip("/") or "/"
        if normalized_entry == normalized_remote_dir:
            continue

        name_only = posixpath.basename(entry.rstrip("/"))
        if not name_only or name_only in (".", ".."):
            continue
        full_entry = f"/{name_only}" if remote_dir == "/" else f"{remote_dir.rstrip('/')}/{name_only}"

        try:
            ftp.cwd(name_only)
            dirs.append(full_entry.rstrip("/") or "/")
            ftp.cwd(remote_dir)
        except ftplib.error_perm:
            files.append(full_entry)
            try:
                ftp.cwd(remote_dir)
            except ftplib.error_perm:
                pass

    try:
        ftp.cwd(start_pwd)
    except ftplib.error_perm:
        pass

    return files, dirs


def list_remote_children(ftp: ftplib.FTP_TLS, remote_dir: str) -> Tuple[List[str], List[str]]:
    try:
        return _list_remote_children_mlsd(ftp, remote_dir)
    except (AttributeError, ftplib.error_perm, socket.timeout, TimeoutError, EOFError) as exc:
        log(f"Aviso: MLSD falhou em {remote_dir}, usando fallback NLST ({exc}).")
        return _list_remote_children_nlst(ftp, remote_dir)


def purge_remote_directory(ftp: ftplib.FTP_TLS, server_dir: str) -> int:
    """Delete all files/subdirectories inside server_dir, preserving server_dir."""
    root = normalize_remote_dir(server_dir)
    deleted_files = 0

    if root != "/":
        try:
            ftp.cwd(root)
            ftp.cwd("/")
        except ftplib.error_perm:
            ftp.mkd(root)
            return 0

    to_visit = [root]
    discovered_dirs: List[str] = []

    while to_visit:
        current = to_visit.pop()
        files, dirs = list_remote_children(ftp, current)

        for remote_file in files:
            if remove_remote_file(ftp, remote_file):
                deleted_files += 1

        for directory in dirs:
            discovered_dirs.append(directory)
            to_visit.append(directory)

    # Remove subdirectories from deepest to shallowest.
    for directory in sorted(set(discovered_dirs), key=lambda item: item.count("/"), reverse=True):
        if directory in ("", "/") or directory == root:
            continue
        try:
            ftp.rmd(directory)
        except ftplib.error_perm as exc:
            log(f"Aviso ao remover diretorio {directory}: {exc}")

    return deleted_files


def remove_empty_remote_dirs(ftp: ftplib.FTP_TLS, candidates: Iterable[str]) -> None:
    # Remove from deepest path to highest parent.
    for directory in sorted(set(candidates), key=lambda item: item.count("/"), reverse=True):
        if not directory or directory == "/":
            continue
        try:
            ftp.rmd(directory)
        except ftplib.error_perm:
            # Not empty or no permission: ignore.
            continue


def connect_ftps(*, server: str, username: str, password: str, port: int, timeout: int) -> TolerantFTP_TLS:
    ftp = TolerantFTP_TLS()
    ftp.connect(host=server, port=port, timeout=timeout)
    ftp.login(user=username, passwd=password)
    ftp.prot_p()
    ftp.set_pasv(True)
    return ftp


def delete_known_remote_paths(
    ftp: ftplib.FTP_TLS,
    *,
    server_dir: str,
    relative_paths: Iterable[str],
) -> int:
    deleted_count = 0
    deleted_parent_dirs: Set[str] = set()
    seen: Set[str] = set()

    for relative_posix in sorted(set(relative_paths)):
        relative = (relative_posix or "").strip().lstrip("/")
        if not relative or relative in seen:
            continue
        seen.add(relative)
        remote_path = remote_join(server_dir, relative)
        if remove_remote_file(ftp, remote_path):
            deleted_count += 1
            deleted_parent_dirs.add(posixpath.dirname(remote_path))

    remove_empty_remote_dirs(ftp, deleted_parent_dirs)
    return deleted_count


def deploy_via_ftps(
    *,
    server: str,
    username: str,
    password: str,
    port: int,
    timeout: int,
    server_dir: str,
    targets: List[DeployTarget],
    previous_state: Dict[str, Dict[str, str]],
) -> Tuple[Dict[str, Dict[str, str]], int, int]:
    current_state: Dict[str, Dict[str, str]] = {}

    for target in targets:
        file_hash = sha1_file(target.local_path)
        metadata = {"sha1": file_hash}
        current_state[target.relative_posix] = metadata

    log(f"Arquivos considerados para deploy: {len(targets)}")
    log("Modo sincronizacao: limpeza remota completa + upload completo.")

    uploaded_count = 0
    deleted_count = 0
    remote_dir_cache: Set[str] = set()

    ftp = TolerantFTP_TLS()
    ftp.connect(host=server, port=port, timeout=timeout)
    ftp.login(user=username, passwd=password)
    ftp.prot_p()
    ftp.set_pasv(True)

    try:
        known_remote_relatives = set(previous_state.keys()).union(
            target.relative_posix for target in targets
        )
        normalized_server_dir = normalize_remote_dir(server_dir)

        if normalized_server_dir == "/":
            log(
                "Diretorio remoto raiz detectado (/). "
                "Usando limpeza por manifesto de arquivos para evitar timeout de listagem."
            )
            deleted_count = delete_known_remote_paths(
                ftp,
                server_dir=server_dir,
                relative_paths=known_remote_relatives,
            )
        else:
            try:
                deleted_count = purge_remote_directory(ftp, server_dir)
            except FTP_RETRY_ERRORS as exc:
                log(
                    "Aviso: purge remoto completo falhou; "
                    f"fallback para limpeza por manifesto ({exc})."
                )
                try:
                    ftp.quit()
                except Exception:
                    ftp.close()

                ftp = connect_ftps(
                    server=server,
                    username=username,
                    password=password,
                    port=port,
                    timeout=timeout,
                )
                deleted_count = delete_known_remote_paths(
                    ftp,
                    server_dir=server_dir,
                    relative_paths=known_remote_relatives,
                )

        log(f"Arquivos removidos no remoto antes do upload: {deleted_count}")

        max_upload_retries = 4
        for target in targets:
            remote_path = remote_join(server_dir, target.relative_posix)
            for attempt in range(1, max_upload_retries + 1):
                try:
                    ensure_remote_dirs(ftp, remote_path, remote_dir_cache)
                    with target.local_path.open("rb") as file_obj:
                        ftp.storbinary(f"STOR {remote_path}", file_obj)
                    uploaded_count += 1
                    break
                except FTP_RETRY_ERRORS as exc:
                    if attempt >= max_upload_retries:
                        raise
                    log(
                        f"Aviso: falha no upload de {remote_path} "
                        f"(tentativa {attempt}/{max_upload_retries}): {exc}. Reconectando."
                    )
                    try:
                        ftp.quit()
                    except Exception:
                        ftp.close()
                    ftp = connect_ftps(
                        server=server,
                        username=username,
                        password=password,
                        port=port,
                        timeout=timeout,
                    )
                    remote_dir_cache.clear()
    finally:
        try:
            ftp.quit()
        except Exception:
            ftp.close()

    return current_state, uploaded_count, deleted_count


def main() -> None:
    args = parse_args()
    script_dir = Path(__file__).resolve().parent
    repo_root = args.repo_root.resolve() if args.repo_root else find_repo_root(script_dir)
    build_dir = (repo_root / args.build_dir).resolve() if not args.build_dir.is_absolute() else args.build_dir.resolve()
    state_file = (repo_root / args.state_file).resolve() if not args.state_file.is_absolute() else args.state_file.resolve()

    log(f"Repo root: {repo_root}")
    log(f"Build dir: {build_dir}")

    run_command(["flutter", "pub", "get"], cwd=repo_root)
    run_command(
        ["flutter", "build", "web", "--release", "--no-wasm-dry-run", "--base-href", args.base_href],
        cwd=repo_root,
    )

    if not build_dir.exists():
        fail(f"Diretorio de build nao encontrado: {build_dir}")

    generate_htaccess(build_dir, args.base_href)

    targets = collect_deploy_targets(build_dir)
    if not targets:
        fail("Nenhum arquivo de deploy encontrado apos o build.")

    if args.build_only:
        log("Modo build-only: upload FTPS ignorado.")
        return

    deploy_env = resolve_deploy_env(args.deploy_env)
    log(f"Deploy env: {deploy_env}")

    env_file = resolve_env_file(repo_root, script_dir, args.env_file, deploy_env)
    log(f"Arquivo de secrets: {env_file}")
    env_values = load_env_file(env_file)
    merged_env = {**env_values, **os.environ}
    validate_required_secrets(merged_env)

    ftp_server = merged_env["WEB_FTP_SERVER"]
    ftp_username = merged_env["WEB_FTP_USERNAME"]
    ftp_password = merged_env["WEB_FTP_PASSWORD"]
    ftp_port_text = merged_env.get("WEB_FTP_PORT", "21").strip()

    try:
        ftp_port = int(ftp_port_text)
    except ValueError:
        fail(f"WEB_FTP_PORT invalido: {ftp_port_text}")
        raise AssertionError("unreachable")

    previous_state = load_state(state_file)
    new_state, uploaded_count, deleted_count = deploy_via_ftps(
        server=ftp_server,
        username=ftp_username,
        password=ftp_password,
        port=ftp_port,
        timeout=args.timeout,
        server_dir=args.server_dir,
        targets=targets,
        previous_state=previous_state,
    )
    save_state(state_file, new_state)

    log(f"Deploy concluido. Uploads: {uploaded_count}, removidos no remoto: {deleted_count}")
    log(f"State file atualizado em: {state_file}")


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as exc:
        fail(f"Comando falhou com exit code {exc.returncode}: {' '.join(exc.cmd)}", exit_code=exc.returncode)
