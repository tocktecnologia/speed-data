# OP06 - Speed Pay Monetizacao

## Feature branch

`feature/op06-speed-pay-monetizacao`

## Script de pre-voo (obrigatorio)

```powershell
$feature = "feature/op06-speed-pay-monetizacao"
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
- Projeto ainda nao possui modulo Speed Pay consolidado.
- Premissa absoluta: nao quebrar operacao de evento e piloto.

Objetivo:
Implementar camada inicial de monetizacao por evento com conciliacao simples e trilha para assinatura futura.

Escopo minimo:
1) Estrutura de cobranca por inscricao (valor, moeda, status).
2) Fluxo manual de confirmacao de pagamento (Pix/manual) no admin.
3) Visao do piloto com status financeiro da inscricao.
4) Relatorio basico por evento (total inscritos, pagos, pendentes).

Arquivos candidatos:
- lib/features/services/firestore_service.dart
- lib/features/screens/admin/event_registration_screen.dart
- lib/features/screens/pilot/pilot_events_screen.dart
- lib/features/models/event_model.dart
- docs/APP_SPECIFICATIONS.md (se houver novo contrato de dados)

Regras de seguranca:
- Comecar com modelo simples e auditavel.
- Nao acoplar gateway externo nesta primeira entrega.
- Preservar todos os fluxos atuais de inscricao e sessao.

Validacao minima:
- flutter analyze
- admin altera status financeiro e piloto enxerga atualizacao
- relatorio por evento fecha com dados de inscricao
- sem impacto nos fluxos de live/telemetria

Entrega esperada:
- MVP Speed Pay operacional (manual)
- base preparada para evoluir para assinatura
- lista de arquivos alterados
```

## Criterio de aceite

- Existe fluxo financeiro minimo por inscricao.
- Time operacional consegue conciliar pagos x pendentes.
- Base pronta para evolucao de monetizacao sem retrabalho grande.
