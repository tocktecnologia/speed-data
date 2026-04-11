# Modulos De Operacao

## Objetivo

Este documento organiza os modulos operacionais do produto e aponta o script de desenvolvimento de cada feature.

## Mapa De Modulos

| Modulo | Macro Produto | Objetivo Pratico | Script |
|---|---|---|---|
| OP01 - Eventos Inscricao MVP | Speed Eventos | Garantir entrada de pilotos e status financeiro basico | `docs/planning/scripts/OP01_EVENTOS_INSCRICAO_MVP.md` |
| OP02 - Live Comunicacao Pista | Speed Eventos + Speed Chrono | Entregar alertas de bandeira/box e mensagens em tempo real | `docs/planning/scripts/OP02_LIVE_COMUNICACAO_PISTA.md` |
| OP03 - Operacao Evento Oficial | Speed Eventos | Rodar evento oficial com cronograma, controle e estabilidade | `docs/planning/scripts/OP03_OPERACAO_EVENTO_OFICIAL.md` |
| OP04 - Speed Chrono Core | Speed Chrono | Aumentar valor para piloto com comparacao e analise de volta | `docs/planning/scripts/OP04_SPEED_CHRONO_CORE.md` |
| OP05 - Coach Remoto Equipe | Speed Chrono + Team | Permitir acompanhamento remoto multi piloto por coach/equipe | `docs/planning/scripts/OP05_COACH_REMOTO_EQUIPE.md` |
| OP06 - Speed Pay Monetizacao | Speed Pay | Estruturar cobranca por evento e trilha de assinatura | `docs/planning/scripts/OP06_SPEED_PAY_MONETIZACAO.md` |

## Regra Padrao Para Todos Os Scripts

- Antes de qualquer desenvolvimento:
  - confirmar branch `develop`;
  - criar branch `feature/<nome-da-feature>`;
  - executar somente o escopo do modulo.
- Nao executar scripts agora. Os documentos foram preparados para execucao posterior.
