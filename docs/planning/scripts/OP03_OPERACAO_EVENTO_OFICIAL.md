# OP03 - Operacao Evento Oficial

## Feature branch

`feature/op03-operacao-evento-oficial`

## Script de pre-voo (obrigatorio)

```powershell
$feature = "feature/op03-operacao-evento-oficial"
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
- Base atual ja possui eventos, sessoes, race control e resultados.
- Premissa absoluta: nao quebrar fluxo operacional existente.

Objetivo:
Concluir o pacote de operacao de evento oficial com cronograma, controle central e estabilidade de uso em dia de prova.

Escopo minimo:
1) Garantir cronograma de evento claro para piloto e admin.
2) Consolidar painel admin com comandos essenciais (bandeira, box, mensagem).
3) Garantir lista de participantes ativa e consistente por sessao.
4) Revisar caminho de resultados publicos por sessao.
5) Criar checklist operacional no app/admin para abertura e encerramento de sessao.

Arquivos candidatos:
- lib/features/screens/admin/event_list_screen.dart
- lib/features/screens/admin/event_registration_screen.dart
- lib/features/screens/admin/race_control_screen.dart
- lib/features/screens/pilot/pilot_event_schedule_screen.dart
- lib/pages/public_results_page_widget.dart
- firebase/functions/index.js (resultados/public session)

Regras de seguranca:
- Nao mexer em contrato de dados sem manter compatibilidade.
- Nao quebrar rota atual de Home/Role routing.
- Preservar desempenho em consulta de passings/results.

Validacao minima:
- flutter analyze
- fluxo completo de sessao: agendar -> iniciar -> controlar -> finalizar -> publicar resultado
- smoke test de piloto e admin em paralelo

Entrega esperada:
- melhorias operacionais no fluxo de evento
- checklist de cenarios validados
- lista de arquivos alterados
```

## Criterio de aceite

- Operacao de sessao funciona ponta a ponta.
- Cronograma e participantes ficam visiveis em tempo real.
- Resultado final por sessao pode ser consultado sem inconsistencias.
