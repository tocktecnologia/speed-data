# Plano de Implementacao - Tela Lap Times (RaceChrono-like)

## Objetivo

Evoluir a tela `Lap Times` para um padrao semelhante ao RaceChrono, com foco em:

- analise detalhada por volta;
- comparacao flexivel entre voltas;
- visualizacao grafica/mapa por modo;
- operacao consistente com o modelo offline-first ja implementado.

## Escopo Funcional Alvo

### 1) Header fixo com Optimal Lap

- Exibir sempre `Optimal Lap` no topo.
- Calculo: soma dos melhores setores validos da sessao.
- Permitir uso da volta ideal como referencia de comparacao.
- Preparar exportacao para KML (fase dedicada abaixo).

### 2) Modos de exibicao

- `Sectors`: tabela de setores por volta + mapa de detalhes com ganho/perda (verde/vermelho) vs volta de comparacao.
- `Splits`: tabela de parciais acumuladas + mapa de qualidade de sinal GPS (verde/amarelo/laranja/vermelho).
- `Trap Speeds`: tabela de velocidade nas linhas + mapa colorido por velocidade absoluta.
- `High/Low`: tabela com maxima/minima/media por volta + mapa com picos, vales e aceleracao longitudinal.
- `Information`: dados gerais da volta (tempo, distancia, inicio, notas e metadados).

### 3) Analise e comparacoes

- `Result mode`: alternar entre `Absolute` e `Difference`.
- Tabela com codigos de cor:
  - azul para volta de comparacao;
  - verde para melhor que referencia;
  - vermelho para pior que referencia.
- Seletor de `Comparison Lap`:
  - padrao: melhor volta valida da sessao;
  - alternativa: qualquer volta da sessao;
  - opcional fase 2: volta de sessoes anteriores.

### 4) Gestao de voltas

- Acao `Mark Invalid` na UI para invalidar/revalidar volta.
- Filtro `Hide invalid` para esconder voltas invalidas da tabela.
- Voltas invalidas nao entram em `Optimal Lap`.

### 5) Graph View

- Tela de grafico comparativo (volta selecionada x volta referencia).
- Canais minimos: velocidade e altitude.
- Canais opcionais: OBD-II quando disponivel.
- Zoom nos eixos X (distancia) e Y (valor), com cursor/scrub sincronizado.

## Estado Atual no Projeto (Resumo)

Ja existe base funcional em:

- `lib/features/screens/pilot/lap_times_screen.dart`
- `lib/features/screens/pilot/widgets/lap_times_*`

Ja implementado:

- 5 modos de tabela (`Sectors`, `Splits`, `Trap Speeds`, `High/Low`, `Information`);
- `Optimal Lap` e resumo com dados de `summary`;
- filtro de validade aplicado na referencia.

Lacunas principais para atingir alvo RaceChrono:

- falta `Result mode` (absoluto/delta) global;
- falta seletor robusto de `Comparison Lap`;
- falta `Details Map` por modo;
- falta `Mark Invalid` e `Hide invalid` na experiencia de uso;
- falta `Graph View` comparativo;
- falta exportacao KML da volta ideal.

## Arquitetura Proposta

### Camada de apresentacao

- Criar controlador dedicado: `LapTimesController` (ChangeNotifier) para estado da tela.
- Estado minimo:
  - `selectedMode`
  - `resultMode` (`absolute` | `difference`)
  - `comparisonLapId`
  - `selectedLapId`
  - `hideInvalid`
  - `showDetailsMap`
  - `showGraph`
- Novos widgets:
  - `lap_times_toolbar.dart`
  - `lap_times_comparison_picker.dart`
  - `lap_times_details_map.dart`
  - `lap_times_graph_view.dart`

### Camada de dados

- Manter fonte principal de `laps`, `crossings`, `summary` no Firestore.
- Introduzir estrutura para traçado detalhado por volta (`lap trace`) para mapa/grafico.
- Recomendacao: armazenar trace em Cloud Storage (JSON comprimido) e referenciar no doc da volta:
  - evita limite de tamanho de documento do Firestore;
  - reduz custo de leitura repetida de arrays grandes;
  - facilita cache local por arquivo.

Contrato sugerido no doc da volta:

- `trace_ref`: path/URL do arquivo de trace;
- `trace_stats`: `samples`, `distance_m`, `has_altitude`, `has_gps_quality`, `has_obd`.

Contrato sugerido de trace (JSON):

- `samples[]` com:
  - `t_ms`
  - `lat`, `lng`
  - `distance_m`
  - `speed_mps`
  - `altitude_m`
  - `accel_long_mps2`
  - `gps_quality` (0-3)
  - `sat_count` (quando houver)
  - `obd` (map opcional)

### Regras de comparacao

- Comparacao sempre contra `comparisonLap`.
- Em `difference`:
  - tempo: `lap - comparison` (negativo = melhor);
  - velocidade: `lap - comparison` (positivo = melhor).
- Cores:
  - melhor: verde;
  - pior: vermelho;
  - referencia: azul.

## Plano por Fases

### Fase 0 - Contrato e UX base

- Definir contratos finais no `APP_SPECIFICATIONS`.
- Definir estados de tela e fluxo de interacao (toolbar e seletores).
- Definir padrao de cores e legenda unificada por modo.

Entrega:

- ADR curto em `docs` com decisao de armazenamento de trace.
- mock de toolbar com toggles e seletor de comparacao.

### Fase 1 - Result Mode + Comparison Lap

- Implementar alternancia `Absolute/Difference`.
- Implementar selector de volta de comparacao (sessao atual).
- Aplicar delta nas 5 tabelas com colorizacao padrao.

Arquivos alvo:

- `lib/features/screens/pilot/lap_times_screen.dart`
- `lib/features/screens/pilot/widgets/lap_times_*`
- `lib/features/services/firestore_service.dart` (se precisar consulta adicional)

### Fase 2 - Invalidacao e filtro

- Acao `Mark Invalid` por volta (UI + persistencia).
- Filtro `Hide invalid`.
- Garantir que `Optimal Lap` ignore invalidas.

Arquivos alvo:

- widgets de tabela
- service de escrita de lap flag
- regras Firestore (se necessarias)

### Fase 3 - Details Map por modo

- Criar `lap_times_details_map.dart`.
- Camadas:
  - `Sectors`: delta por trecho;
  - `Splits`: qualidade de sinal;
  - `Trap Speeds`: gradiente de velocidade;
  - `High/Low`: marcadores high/low + aceleracao/frenagem.
- Sincronizar hover/tap tabela <-> mapa.

Dependencias:

- trace por volta acessivel pela UI.

### Fase 4 - Graph View

- Tela de grafico comparativo com overlay claro/escuro.
- Canais iniciais: velocidade e altitude.
- Zoom X/Y + cursor sincronizado.
- Preparar hook para canais OBD opcionais.

### Fase 5 - Exportacao KML da Optimal Lap

- Gerar KML da volta ideal a partir dos melhores setores.
- Opcoes: compartilhar arquivo ou salvar localmente.
- Garantir consistencia com laps invalidas ocultadas do calculo.

### Fase 6 - Performance, cache e offline

- Cache local de traces (arquivo + TTL).
- Carregamento incremental para sessoes longas.
- Limitar resolucao de render (downsample) para manter FPS.

### Fase 7 - Testes e rollout

- Testes unitarios:
  - calculo de delta;
  - escolha de referencia;
  - optimal lap com invalidas.
- Testes de widget:
  - render por modo;
  - estados de toolbar;
  - colorizacao correta.
- Testes manuais:
  - mapa e grafico em dispositivo real;
  - alternancia de conexao (offline/online).

## Backlog Tecnico Sugerido (Lap Times V2)

- `LT-001` Toolbar de analise (result mode + comparison + hide invalid)
- `LT-002` Marcacao de volta invalida na UI
- `LT-003` Contrato de lap trace + persistencia
- `LT-004` Details map - Sectors
- `LT-005` Details map - Splits (gps quality)
- `LT-006` Details map - Trap Speeds
- `LT-007` Details map - High/Low + aceleracao
- `LT-008` Graph view comparativo
- `LT-009` Export KML da Optimal Lap
- `LT-010` Testes e hardening de performance

## Criterios de Aceite (DoD Lap Times V2)

- `Optimal Lap` visivel no topo e consistente com laps validas.
- 5 modos exibem dados em `absolute` e `difference`.
- Comparacao por volta selecionavel pelo usuario.
- Invalidacao de volta funcional e refletida em toda a tela.
- Details map funcional para os 5 modos.
- Graph view funcional com overlay e zoom.
- Performance aceitavel em sessao com >= 50 voltas sem travamentos severos.

## Riscos e Mitigacoes

- Falta de dado de satelite por amostra:
  - mitigacao: usar bucket por `accuracy` como fallback quando `sat_count` nao existir.
- Alto volume de trace no Firestore:
  - mitigacao: usar Cloud Storage + cache local.
- Inconsistencia entre tabela e mapa:
  - mitigacao: chave unica por `lap_number + sample_index` e teste de sincronizacao.
- Complexidade do grafico:
  - mitigacao: liberar por etapas (speed/altitude primeiro, OBD depois).

## Dependencias

- Backend/ingest para gerar e publicar `trace_ref` por volta.
- Ajustes em modelo Dart para trace.
- Possivel ajuste em regras/indices Firestore para invalidacao por piloto/admin.
- Definicao de permissao para exportacao e compartilhamento de arquivo KML.
