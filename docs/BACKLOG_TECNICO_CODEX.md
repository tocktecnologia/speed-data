# Backlog Tecnico - Execucao via Codex

Este documento consolida as mudancas e tarefas tecnicas para evoluir a coleta e analise de voltas (Lap Times) com dados robustos para estatistica e IA.

## Objetivo

Implementar um pipeline de telemetria que:
- grave cruzamentos de checkpoints (traps) de forma estruturada;
- gere voltas por sessao com setores, splits e velocidades;
- mantenha compatibilidade com o fluxo atual;
- entregue dados prontos para a nova area `Lap Times` no app do piloto.

## Estado Atual (resumo)

- `ingestTelemetry` grava voltas em `races/{raceId}/participants/{uid}/laps`.
- Fechamento de volta ocorre em `cp_0` e grava `totalLapTime`.
- `passings` hoje e focado no fechamento da volta (`cp_0`), com pouco enriquecimento para checkpoints intermediarios.
- `processTelemetry` atualiza `participants.current` e envia dados para BigQuery.
- A aba de configuracao de `Timelines` no admin ainda esta pendente.

## Mudancas de Arquitetura (alvo)

### 1) Persistencia por sessao

Adicionar estrutura por sessao:

`races/{raceId}/participants/{uid}/sessions/{sessionId}/state/current`  
`races/{raceId}/participants/{uid}/sessions/{sessionId}/crossings/{crossingId}`  
`races/{raceId}/participants/{uid}/sessions/{sessionId}/laps/{lapId}`  
`races/{raceId}/participants/{uid}/sessions/{sessionId}/analysis/summary`

### 2) Entidades principais

- `crossings`: evento de cruzamento por trap/checkpoint.
- `laps`: agregado da volta (splits, setores, velocidades, validade).
- `summary`: melhor volta, volta ideal e melhores setores por sessao.
- `state/current`: estado incremental para deduplicacao e sequenciamento.

### 3) Compatibilidade

Manter escrita legada em `participants/{uid}/laps` durante migracao.

## Contrato de Dados Minimo

### `crossings`

Campos obrigatorios:
- `lap_number`
- `checkpoint_index`
- `crossed_at_ms`
- `speed_mps`
- `lat`
- `lng`
- `method` (`nearest_point` ou `interpolated`)
- `distance_to_checkpoint_m`
- `confidence`
- `created_at`

Campos opcionais:
- `sector_time_ms`
- `split_time_ms`

### `laps` (por sessao)

Campos obrigatorios:
- `number`
- `lap_start_ms`
- `lap_end_ms`
- `total_lap_time_ms`
- `points`
- `valid`

Campos recomendados:
- `invalid_reasons` (array)
- `splits_ms` (array)
- `sectors_ms` (array)
- `trap_speeds_mps` (array)
- `speed_stats` (`min_mps`, `max_mps`, `avg_mps`)
- `distance_m`
- `created_at`

### `summary` (por sessao)

Campos:
- `best_lap_ms`
- `optimal_lap_ms`
- `best_sectors_ms`
- `valid_laps_count`
- `total_laps_count`
- `updated_at`

## Backlog Tecnico (pronto para execucao no Codex)

1. [ ] `BT-001` Consolidar source das Cloud Functions  
Arquivos: `firebase/functions/index.js`, `docs/ingestTelemetry.js`, `docs/processTelemetry.js`  
Aceite: uma unica implementacao oficial alinhada com o deploy.

2. [ ] `BT-002` Formalizar contrato de dados de analise  
Arquivo: `docs/APP_SPECIFICATIONS.md`  
Aceite: schema de `crossings`, `laps`, `summary` e `state` documentado.

3. [ ] `BT-003` Escrever dados por sessao  
Arquivo: `firebase/functions/index.js`  
Aceite: escrita em `sessions/{sessionId}/...` quando `sessionId` existir.

4. [ ] `BT-004` Implementar `state/current` por piloto/sessao  
Arquivo: `firebase/functions/index.js`  
Aceite: deduplicacao basica de checkpoint e controle de ordem.

5. [ ] `BT-005` Gravar `crossings` para todo checkpoint  
Arquivo: `firebase/functions/index.js`  
Aceite: cada trap detectado gera documento de crossing.

6. [ ] `BT-006` Fechamento robusto de volta em `cp_0`  
Arquivo: `firebase/functions/index.js`  
Aceite: fecha lap atual, calcula tempo e abre proxima lap.

7. [ ] `BT-007` Persistir `laps` analiticos por sessao  
Arquivo: `firebase/functions/index.js`  
Aceite: lap com `splits`, `sectors`, `trap_speeds`, `speed_stats`, `valid`.

8. [ ] `BT-008` Enriquecer `passings` em checkpoints intermediarios  
Arquivo: `firebase/functions/index.js`  
Aceite: salvar `sector_time`, `split_time` e `trap_speed` por checkpoint.

9. [ ] `BT-009` Validar lap no backend com regra de sessao  
Arquivo: `firebase/functions/index.js`  
Aceite: aplicar `min_lap_time_seconds` e registrar invalidade.

10. [ ] `BT-010` Calcular `summary` e `optimal lap` incremental  
Arquivo: `firebase/functions/index.js`  
Aceite: `analysis/summary` atualizado a cada lap valida.

11. [ ] `BT-011` Preservar compatibilidade legada temporaria  
Arquivo: `firebase/functions/index.js`  
Aceite: telas antigas continuam funcionando sem quebra.

12. [ ] `BT-012` Incluir `sessionId` e metadados no fluxo BigQuery  
Arquivo: `firebase/functions/index.js`  
Aceite: dados exportados segmentaveis por sessao.

13. [ ] `BT-013` Criar modelos Dart de analise  
Arquivos: `lib/features/models/lap_analysis_model.dart`, `lib/features/models/crossing_model.dart`, `lib/features/models/session_analysis_summary_model.dart`  
Aceite: parse/serialize cobrindo o contrato novo.

14. [ ] `BT-014` Expandir `FirestoreService` para analise  
Arquivo: `lib/features/services/firestore_service.dart`  
Aceite: metodos para laps/crossings/summary por sessao.

15. [ ] `BT-015` Criar tela base `Lap Times`  
Arquivo: `lib/features/screens/pilot/lap_times_screen.dart`  
Aceite: tela com seletor de modo e estrutura principal.

16. [ ] `BT-016` Implementar modo `Sectors` com linha `Opt`  
Arquivo: `lib/features/screens/pilot/widgets/lap_times_table.dart`  
Aceite: comparacao por cores (verde/vermelho) vs volta referencia.

17. [ ] `BT-017` Implementar modos `Splits`, `Trap Speeds`, `High/Low`, `Information`  
Arquivos: `lib/features/screens/pilot/widgets/*`  
Aceite: todos os modos consumindo dados persistidos, sem heuristica pesada.

18. [ ] `BT-018` Integrar navegacao no app do piloto  
Arquivo: `lib/features/screens/pilot/pilot_dashboard.dart`  
Aceite: acesso a Lap Times para sessao atual e historica.

19. [ ] `BT-019` Backfill de dados legados  
Arquivos: `firebase/functions/*` (job administrativo)  
Aceite: sessoes recentes com dados minimos para nova tela.

20. [ ] `BT-020` Atualizar regras e indices do Firestore  
Arquivos: `firebase/firestore.rules`, `firebase/firestore.indexes.json`  
Aceite: consultas por sessao sem erro de permissao/index.

21. [ ] `BT-021` Testes backend de calculo de voltas e parciais  
Arquivos: `firebase/functions/*`  
Aceite: cobertura dos casos criticos (deduplicacao, ordem, validade).

22. [ ] `BT-022` Testes Flutter para tela Lap Times  
Arquivos: `test/*`  
Aceite: renderizacao e consistencia dos modos com dados mockados.

23. [ ] `BT-023` Atualizar documentacao final  
Arquivo: `docs/APP_SPECIFICATIONS.md`  
Aceite: arquitetura final e fluxo de dados refletidos no documento.

24. [ ] `BT-024` Integrar `Race Control` com estrutura por sessao  
Arquivos: `lib/features/screens/admin/race_control_screen.dart`, `lib/features/services/firestore_service.dart`  
Aceite: tela usa `sessionId` de forma consistente para controle, exibicao e operacoes de sessao.

25. [ ] `BT-025` Atualizar `Passings Panel` para novos campos de trap/split  
Arquivos: `lib/features/screens/admin/widgets/passings_panel.dart`, `lib/features/models/passing_model.dart`  
Aceite: exibir `sector_time`, `split_time` e `trap_speed` quando disponiveis, mantendo compatibilidade com dados antigos.

26. [ ] `BT-026` Atualizar `Results/Leaderboard` para fonte por sessao  
Arquivos: `lib/features/screens/admin/widgets/leaderboard_panel.dart`, `lib/features/services/firestore_service.dart`  
Aceite: calculos de resultados priorizam dados por sessao e usam resumo analitico quando existir.

27. [ ] `BT-027` Implementar configuracao real de `Timelines` no admin  
Arquivos: `lib/features/screens/admin/session_settings_screen.dart`, `lib/features/models/race_session_model.dart`  
Aceite: admin consegue criar/editar/ordenar linhas de controle (`start_finish`, `split`, `trap`) por sessao.

28. [ ] `BT-028` Propagar `timelines` para backend de ingestao  
Arquivos: `lib/features/services/telemetry_service.dart`, `firebase/functions/index.js`  
Aceite: ingestao usa as linhas configuradas na sessao (nao apenas checkpoints fixos da pista).

29. [ ] `BT-029` Ajustar `AdminMapView` para visualizacao de traps/timelines  
Arquivos: `lib/features/screens/admin/admin_map_view.dart`  
Aceite: mapa admin mostra linhas/traps configurados e facilita validacao visual.

30. [ ] `BT-030` Testes de regressao das telas admin  
Arquivos: `test/*`  
Aceite: fluxo de cronometragem/admin continua funcional com dados legados e novos.

## Ordem Recomendada de Execucao

1. Backend core: `BT-001` a `BT-012`  
2. Flutter data layer: `BT-013` e `BT-014`  
3. UI Lap Times (piloto): `BT-015` a `BT-018`  
4. Migracao e hardening: `BT-019` a `BT-023`  
5. Integracao Admin UI: `BT-024` a `BT-030`

## Definition of Done (DoD)

- Dados de crossing/lap por sessao persistidos e consistentes.
- Melhor volta e volta ideal batem com os calculos de sessao.
- Modos da tela Lap Times funcionam com dados reais.
- Regras e indices atualizados sem regressao nas telas atuais.
- Documentacao tecnica atualizada.
- Fluxo admin (Race Control, Passings, Results e Timelines) funcional com a nova arquitetura.

## Instrucoes Especificas por Tarefa (Codex 5.1-Max)

Use este formato em cada execucao:
- aplicar apenas o escopo da tarefa;
- validar com comando curto;
- registrar no commit somente arquivos relacionados.

### BT-001
- Objetivo: consolidar implementacao final das functions em `firebase/functions/index.js`.
- Passos: comparar com `docs/ingestTelemetry.js` e `docs/processTelemetry.js`, copiar diferencas validas, remover divergencias.
- Validacao: `rg -n "exports.ingestTelemetry|exports.processTelemetry" firebase/functions/index.js`.

### BT-002
- Objetivo: formalizar contrato de dados em `docs/APP_SPECIFICATIONS.md`.
- Passos: adicionar secoes explicitas para `crossings`, `laps` por sessao, `summary`, `state`.
- Validacao: `rg -n "crossings|summary|state/current|sessions/{sessionId}" docs/APP_SPECIFICATIONS.md`.

### BT-003
- Objetivo: escrever dados por sessao no backend.
- Passos: usar `sessionId` para escrever em `participants/{uid}/sessions/{sessionId}/...` sem remover legado.
- Validacao: `rg -n "collection\\('sessions'\\)|sessionId|session" firebase/functions/index.js`.

### BT-004
- Objetivo: implementar `state/current`.
- Passos: criar leitura/escrita de estado incremental por piloto/sessao para checkpoint anterior e timestamp.
- Validacao: `rg -n "state/current|last_checkpoint|last_crossed" firebase/functions/index.js`.

### BT-005
- Objetivo: gravar `crossings` para todos checkpoints.
- Passos: no cruzamento detectado, inserir documento com timestamp, velocidade, checkpoint e confianca.
- Validacao: `rg -n "collection\\('crossings'\\)|checkpoint_index|crossed_at_ms" firebase/functions/index.js`.

### BT-006
- Objetivo: fechamento robusto em `cp_0`.
- Passos: calcular `lap_start_ms`, `lap_end_ms`, `total_lap_time_ms`; abrir proxima lap.
- Validacao: `rg -n "cp_0|totalLapTime|lap_end_ms|nextLap" firebase/functions/index.js`.

### BT-007
- Objetivo: persistir lap analitica.
- Passos: preencher `splits_ms`, `sectors_ms`, `trap_speeds_mps`, `speed_stats`, `valid`.
- Validacao: `rg -n "splits_ms|sectors_ms|trap_speeds_mps|speed_stats|valid" firebase/functions/index.js`.

### BT-008
- Objetivo: enriquecer `passings` intermediarios.
- Passos: gravar `sector_time`, `split_time`, `trap_speed` para checkpoints diferentes de `cp_0`.
- Validacao: `rg -n "sector_time|split_time|trap_speed|checkpoint_index" firebase/functions/index.js`.

### BT-009
- Objetivo: validar lap no backend.
- Passos: aplicar regra de `min_lap_time_seconds` e armazenar motivos em `invalid_reasons`.
- Validacao: `rg -n "min_lap_time_seconds|invalid_reasons|valid" firebase/functions/index.js`.

### BT-010
- Objetivo: atualizar `analysis/summary`.
- Passos: recalcular `best_lap_ms`, `best_sectors_ms`, `optimal_lap_ms` a cada lap valida.
- Validacao: `rg -n "analysis|summary|optimal_lap_ms|best_sectors_ms" firebase/functions/index.js`.

### BT-011
- Objetivo: manter compatibilidade legada.
- Passos: garantir escrita em `participants/{uid}/laps` durante migracao e leitura fallback no app.
- Validacao: `rg -n "collection\\('laps'\\).*participants|fallback|legacy" firebase/functions/index.js lib/features/services/firestore_service.dart`.

### BT-012
- Objetivo: enriquecer payload de BigQuery.
- Passos: incluir `sessionId` e campos analiticos no payload publicado/processado.
- Validacao: `rg -n "bigquery|sessionId|raw_points|insert" firebase/functions/index.js`.

### BT-013
- Objetivo: criar modelos Dart de analise.
- Passos: adicionar modelos com `fromMap`/`toMap` e parse seguro de tipos.
- Validacao: `rg -n "class LapAnalysis|class Crossing|class SessionAnalysisSummary" lib/features/models`.

### BT-014
- Objetivo: expandir `FirestoreService`.
- Passos: adicionar streams/metodos para laps analiticos, crossings e summary por sessao.
- Validacao: `rg -n "getSession.*Laps|getSession.*Crossings|getSession.*Summary" lib/features/services/firestore_service.dart`.

### BT-015
- Objetivo: criar tela base `Lap Times`.
- Passos: scaffold da tela, header de sessao e seletor de modo.
- Validacao: `rg -n "class LapTimesScreen|Mode|Sectors|Splits" lib/features/screens/pilot`.

### BT-016
- Objetivo: implementar modo `Sectors`.
- Passos: tabela com linha `Opt`, comparacao por referencia e cores por delta.
- Validacao: `rg -n "Opt|sector|delta|color" lib/features/screens/pilot/widgets`.

### BT-017
- Objetivo: implementar modos restantes.
- Passos: criar widgets para `Splits`, `Trap Speeds`, `High/Low`, `Information` e conectar aos dados.
- Validacao: `rg -n "Splits|Trap Speeds|High/Low|Information" lib/features/screens/pilot/widgets`.

### BT-018
- Objetivo: integrar navegacao para `Lap Times`.
- Passos: adicionar entrada no dashboard/tela relevante com parametros de sessao.
- Validacao: `rg -n "LapTimesScreen|Navigator.push|GoRouter" lib/features/screens/pilot`.

### BT-019
- Objetivo: backfill de dados legados.
- Passos: criar job administrativo para reconstruir `crossings/laps/summary` a partir de dados existentes.
- Validacao: `rg -n "backfill|rebuild|migrate" firebase/functions`.

### BT-020
- Objetivo: atualizar regras e indices.
- Passos: incluir paths de sessao nas rules e indices para consultas por `sessionId`, `number`, `valid`.
- Validacao: `rg -n "sessions|crossings|summary|indexes|rules" firebase/firestore.rules firebase/firestore.indexes.json`.

### BT-021
- Objetivo: testes backend.
- Passos: criar testes para deduplicacao, ordem de checkpoint, fechamento de lap e validade.
- Validacao: executar script de testes da pasta functions.

### BT-022
- Objetivo: testes Flutter da nova area.
- Passos: cobrir render e dados dos modos com fixtures/mocks.
- Validacao: `flutter test` com foco em `lap_times`.

### BT-023
- Objetivo: atualizar documentacao final.
- Passos: refletir arquitetura final no `APP_SPECIFICATIONS`.
- Validacao: `rg -n "Lap Times|crossings|sessions/{sessionId}|optimal" docs/APP_SPECIFICATIONS.md`.

### BT-024
- Objetivo: integrar `Race Control` com sessao.
- Passos: garantir que selecao e operacoes usem sempre `sessionId` ativo.
- Validacao: `rg -n "sessionId|active session|RaceControl" lib/features/screens/admin/race_control_screen.dart`.

### BT-025
- Objetivo: atualizar `Passings Panel`.
- Passos: exibir novos campos (`split_time`, `trap_speed`) sem quebrar layout existente.
- Validacao: `rg -n "split_time|trap_speed|sector_time" lib/features/screens/admin/widgets/passings_panel.dart`.

### BT-026
- Objetivo: atualizar `Results/Leaderboard`.
- Passos: priorizar fonte por sessao e usar resumo analitico quando disponivel.
- Validacao: `rg -n "session|summary|best_lap|optimal" lib/features/screens/admin/widgets/leaderboard_panel.dart`.

### BT-027
- Objetivo: implementar `Timelines` no admin.
- Passos: trocar placeholder por CRUD de linhas (`start_finish`, `split`, `trap`) e persistencia em sessao.
- Validacao: `rg -n "Timelines|split|trap|start_finish" lib/features/screens/admin/session_settings_screen.dart lib/features/models/race_session_model.dart`.

### BT-028
- Objetivo: propagar `timelines` para ingestao.
- Passos: enviar linhas da sessao no payload de telemetria e consumir no backend.
- Validacao: `rg -n "timelines|checkpoints|sendTelemetryBatch|session" lib/features/services/telemetry_service.dart firebase/functions/index.js`.

### BT-029
- Objetivo: ajustar `AdminMapView`.
- Passos: desenhar linhas/traps configuradas e diferenciar visualmente por tipo.
- Validacao: `rg -n "trap|timeline|polyline|marker" lib/features/screens/admin/admin_map_view.dart`.

### BT-030
- Objetivo: testes de regressao admin.
- Passos: cobrir fluxo de bandeiras, passings, resultados e troca de sessao.
- Validacao: executar testes admin no Flutter e validar cenarios manuais principais.
