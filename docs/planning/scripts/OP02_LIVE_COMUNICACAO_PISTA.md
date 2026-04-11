# OP02 - Live Comunicacao Pista

## Feature branch

`feature/op02-live-comunicacao-pista`

## Script de pre-voo (obrigatorio)

```powershell
$feature = "feature/op02-live-comunicacao-pista"
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
- Projeto Flutter + Firebase com recursos de live ja existentes.
- Premissa absoluta: nao quebrar funcionalidades de pista ja operacionais.

Objetivo:
Fortalecer comunicacao em tempo real para piloto durante sessao: bandeira, box e alertas criticos com fallback visual confiavel.

Escopo minimo:
1) Revisar fluxo de recepcao de bandeira e status de box no piloto.
2) Garantir mensagens de alerta com prioridade visual (ex.: BOX, RED FLAG, YELLOW).
3) Melhorar resiliencia de stream/reconexao no modo live.
4) Padronizar feedback de erro/reconexao para nao deixar piloto sem contexto.

Arquivos candidatos:
- lib/features/screens/pilot/active_race_screen.dart
- lib/features/screens/admin/race_control_screen.dart
- lib/features/screens/admin/widgets/control_flags.dart
- lib/features/services/firestore_service.dart
- firebase/functions/index.js (somente se necessario para contrato de alerta)

Regras de seguranca:
- Nao alterar comportamento de ingestao de telemetria sem necessidade.
- Nao remover comandos atuais de controle de sessao.
- Preservar semantica STOP vs FINISH.

Validacao minima:
- flutter analyze
- teste manual em 2 clientes: admin envia comando, piloto recebe em tempo real
- reconexao simulada: stream cai e retorna sem travar interface

Entrega esperada:
- implementacao com foco operacional
- lista de cenarios cobertos
- lista de arquivos alterados
```

## Criterio de aceite

- Piloto recebe alertas criticos em tempo real com fallback claro.
- Admin controla bandeira/box sem regressao.
- Fluxo live permanece estavel apos reconexao.
