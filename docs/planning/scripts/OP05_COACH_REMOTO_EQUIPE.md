# OP05 - Coach Remoto Equipe

## Feature branch

`feature/op05-coach-remoto-equipe`

## Script de pre-voo (obrigatorio)

```powershell
$feature = "feature/op05-coach-remoto-equipe"
git checkout develop
git pull --ff-only origin develop
$current = git branch --show-current
if ($current -ne "develop") { throw "Branch atual precisa ser develop. Atual: $current" }
git checkout -b $feature
git branch --show-current
```

## Prompt para implementar a feature

```text
Contexto:
- Projeto ja possui base de team module e dados por sessao.
- Premissa absoluta: nao quebrar fluxo de admin e piloto.

Objetivo:
Permitir operacao remota de coach/equipe com visao de multiplos pilotos e dados em tempo real.

Escopo minimo:
1) Dashboard de equipe com lista de pilotos vinculados.
2) Cartoes live por piloto (status sessao, ultimo tempo relevante, alerta ativo).
3) Filtro por evento/sessao para acompanhamento remoto.
4) Acesso controlado por permissao de equipe (sem expor dados de outros times).

Arquivos candidatos:
- lib/features/screens/team/team_dashboard_screen.dart
- lib/features/models/team_model.dart
- lib/features/services/firestore_service.dart
- firebase/functions/index.js (se precisar reforcar autorizacao de leitura/envio de alerta)

Regras de seguranca:
- Respeitar escopo de permissao por equipe.
- Nao alterar role de usuario existente sem migracao explicita.
- Nao causar regressao no fluxo de piloto/admin.

Validacao minima:
- flutter analyze
- membro de equipe ve apenas pilotos permitidos
- status live atualiza em tempo real
- envio/limpeza de alerta continua funcionando com permissao correta

Entrega esperada:
- dashboard remoto minimo funcional
- validacao de permissao de acesso
- lista de arquivos alterados
```

## Criterio de aceite

- Coach/equipe acompanha multiplos pilotos remotamente.
- Escopo de dados respeita permissoes por time.
- Fluxo atual de operacao nao sofre regressao.
