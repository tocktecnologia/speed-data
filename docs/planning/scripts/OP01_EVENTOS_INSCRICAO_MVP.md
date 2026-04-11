# OP01 - Eventos Inscricao MVP

## Feature branch

`feature/op01-eventos-inscricao-mvp`

## Script de pre-voo (obrigatorio)

```powershell
$feature = "feature/op01-eventos-inscricao-mvp"
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
- Projeto Flutter + Firebase ja em operacao.
- Premissa absoluta: nao quebrar o que ja funciona hoje.
- Foco deste modulo: inscricao operacional para evento e status financeiro basico.

Objetivo:
Implementar/ajustar o fluxo de inscricao de piloto em evento com status pendente/pago (manual pix), mantendo compatibilidade com telas e colecoes atuais.

Escopo minimo:
1) Modelar persistencia de inscricao de evento (reusar estrutura atual quando possivel).
2) Garantir tela de inscricao do piloto com confirmacao clara.
3) Garantir listagem de inscritos no admin.
4) Adicionar status de pagamento simples: pending/paid + data de confirmacao.
5) Nao remover fluxo legado; evoluir com compatibilidade.

Arquivos candidatos:
- lib/features/services/firestore_service.dart
- lib/features/screens/admin/event_registration_screen.dart
- lib/features/screens/pilot/pilot_events_screen.dart
- lib/features/models/event_model.dart

Regras de seguranca:
- Nao quebrar fluxo de live timer, race control e lap times.
- Nao migrar backend para outro provedor.
- Evitar mudancas amplas sem teste.

Validacao minima:
- flutter analyze
- fluxo piloto: ver evento -> inscrever -> status exibido
- fluxo admin: ver inscritos -> atualizar status pago/pendente
- sem regressao nos fluxos existentes de evento/sessao

Entrega esperada:
- codigo + ajustes de UI necessarios
- resumo objetivo das alteracoes
- lista de arquivos alterados
```

## Criterio de aceite

- Piloto consegue se inscrever e visualizar status.
- Admin consegue listar inscritos e confirmar pagamento manual.
- Fluxos atuais de evento continuam funcionais.
