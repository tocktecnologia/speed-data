# Deploy via GitHub Actions + FTP

Este projeto possui um workflow para build e deploy da versao web via FTP:

- Workflow: `.github/workflows/deploy-web-ftp.yml`
- Build gerado em: `build/web/`

## 1) Configurar secrets no GitHub

No repositorio, acesse: `Settings > Secrets and variables > Actions > New repository secret`.

Crie os secrets:

- `FTP_SERVER`: host FTP (ex.: `ftp.seudominio.com`)
- `FTP_USERNAME`: usuario FTP
- `FTP_PASSWORD`: senha FTP
- `FTP_SERVER_DIR`: diretorio remoto (ex.: `/public_html/` ou `/public_html/app/`)

## 2) Configurar variaveis opcionais

Em `Settings > Secrets and variables > Actions > Variables`, voce pode definir:

- `FTP_PROTOCOL`: `ftp` (padrao) ou `ftps`
- `FTP_PORT`: porta do servidor (padrao `21`)

Se nao configurar, o workflow usa `ftp` e porta `21`.

## 3) Como disparar o deploy

O deploy roda em dois cenarios:

- push para branch `main` ou `master`;
- execucao manual em `Actions > Deploy Flutter Web to FTP > Run workflow`.

## 4) Ajuste de subpasta no servidor (opcional)

Se sua aplicacao rodar em subpasta (ex.: `https://site.com/app/`), ajuste o comando de build:

```yaml
- name: Build web app
  run: flutter build web --release --base-href /app/
```

## 5) Observacoes

- O primeiro deploy pode enviar todos os arquivos.
- Os deploys seguintes enviam apenas diferencas.
- Garanta que o servidor web aponte para os arquivos publicados no `FTP_SERVER_DIR`.
