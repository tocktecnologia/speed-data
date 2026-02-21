# Speed Data - EspecificaÃ§Ãµes do Aplicativo

Plataforma de telemetria e rastreamento GPS em tempo real para corridas (drones/karts/automobilismo).
ConstruÃ­do com **Flutter + FlutterFlow**, usando **Firebase** (Auth, Firestore, Cloud Functions) como backend.

> Este documento Ã© atualizado sempre que houver mudanÃ§as ou adiÃ§Ãµes de funcionalidades.

---

## SumÃ¡rio

- [VisÃ£o Geral](#visÃ£o-geral)
- [Fluxo de AutenticaÃ§Ã£o](#fluxo-de-autenticaÃ§Ã£o)
- [Tela Principal](#tela-principal-roteador)
- [Telas do Piloto](#telas-do-piloto)
- [Telas do Admin](#telas-do-admin)
- [ServiÃ§os](#serviÃ§os-camada-de-dados)
- [Fluxo de Dados](#fluxo-de-dados-principal)
- [Estrutura do Firestore](#estrutura-do-firestore)
- [Contrato de Dados - Lap Times](#contrato-de-dados---lap-times)
- [NavegaÃ§Ã£o](#navegaÃ§Ã£o-gorouter)
- [Stack TecnolÃ³gica](#stack-tecnolÃ³gica)

---

## VisÃ£o Geral

**Speed Data** Ã© um sistema multi-papel com dois perfis principais:

- **Piloto**: participa de corridas, grava telemetria GPS, analisa desempenho
- **Admin**: cria pistas, monitora corridas ao vivo, visualiza leaderboard

### Fluxo Principal

1. Admin cria corrida com checkpoints no mapa
2. Piloto entra na corrida e inicia gravaÃ§Ã£o GPS
3. Telemetria Ã© capturada a cada 50ms e sincronizada a cada 5s para Cloud Functions
4. Cloud Function processa dados, detecta voltas e calcula estatÃ­sticas
5. Admin monitora posiÃ§Ãµes ao vivo e leaderboard
6. Piloto analisa desempenho pÃ³s-corrida (grÃ¡ficos, tempos, intervalos)

---

## Fluxo de AutenticaÃ§Ã£o

### Landing Page

- **Arquivo**: `lib/pages/landing_page_widget.dart`
- **Rota**: `/landingPage`
- **Funcionalidade**: Tela inicial com logo "SPEED DATA". Dois botÃµes de seleÃ§Ã£o de papel: PILOTO e ADMIN. Link "Already have account? Login"
- **NavegaÃ§Ã£o**: Redireciona para Sign Up (com papel) ou Login

### Login

- **Arquivo**: `lib/login/login_widget.dart`
- **Rota**: `/login`
- **Funcionalidade**:
  - Campos: email, senha (com toggle de visibilidade)
  - Dropdown de seleÃ§Ã£o de papel (Pilot/Admin)
  - BotÃ£o "Entrar pelo Google" (Google OAuth)
  - BotÃ£o "Entrar" (email/senha)
  - Link para cadastro
- **Layout**: Responsivo (variaÃ§Ã£o mobile e desktop)
- **NavegaÃ§Ã£o**: Login bem-sucedido vai para HomePage

### Sign Up

- **Arquivo**: `lib/sign_up/sign_up_widget.dart`
- **Rota**: `/signUp`
- **Funcionalidade**:
  - Campos: email, senha, confirmaÃ§Ã£o de senha
  - Dropdown de papel (Pilot/Admin)
  - ValidaÃ§Ã£o: senhas devem coincidir
  - CriaÃ§Ã£o de conta via `authManager.createAccountWithEmail()`
- **NavegaÃ§Ã£o**: Piloto vai para Pilot Profile Setup; Admin vai para HomePage

### Pilot Profile Setup

- **Arquivo**: `lib/sign_up/pilot_profile_setup_widget.dart`
- **Rota**: `/pilotProfileSetup`
- **Funcionalidade**:
  - Campo: nome do piloto (prÃ©-preenchido com displayName)
  - Paleta de 21 cores para escolha da cor do piloto
  - Cor selecionada exibe checkmark e efeito de brilho
  - Salva perfil no Firestore via `FirestoreService.updatePilotProfile()`
- **NavegaÃ§Ã£o**: Vai para HomePage apÃ³s salvar

---

## Tela Principal (Roteador)

### Home Page

- **Arquivo**: `lib/pages/home_page/home_page_widget.dart`
- **Rota**: `/homePage`
- **Funcionalidade**:
  - Busca o papel do usuÃ¡rio no Firestore via `FirestoreService.getUserRole()`
  - Redireciona com base no papel:
    - Admin/Root â†’ AdminDashboard
    - Pilot â†’ PilotDashboard
    - Sem papel â†’ UI de seleÃ§Ã£o de papel
  - Loading spinner enquanto determina o papel
  - AppBar com botÃ£o de logout

---

## Telas do Piloto

### Pilot Dashboard

- **Arquivo**: `lib/features/screens/pilot/pilot_dashboard.dart`
- **Funcionalidade**:
  - Lista de corridas abertas (stream em tempo real via `getOpenRaces()`)
  - Cada card de corrida exibe: nome, status ("Open for registration"), botÃµes de aÃ§Ã£o
  - BotÃ£o "Test GPS": entra na corrida e navega para GpsTestScreen
  - BotÃ£o "Stats": exibe estatÃ­sticas via bottom sheet
  - Navigation drawer com info do usuÃ¡rio e logout
- **Dados exibidos**: Lista de corridas (atualizaÃ§Ã£o em tempo real)

### GPS Test Screen

- **Arquivo**: `lib/features/screens/pilot/gps_test_screen.dart`
- **ParÃ¢metros**: raceId, userId, raceName
- **Funcionalidade**:
  - Mapa Google com checkpoints marcados (A, B, C...)
  - VisualizaÃ§Ã£o da rota com polyline
  - Controles de simulaÃ§Ã£o:
    - Slider de velocidade (m/s ajustÃ¡vel, padrÃ£o 40 m/s)
    - BotÃµes Start/Stop
  - Painel de telemetria: velocidade atual, Hz, coordenadas
  - Rota carregada do Firestore ou calculada dos checkpoints
  - Sistema de buffer/batch para dados de telemetria (sync a cada 5s)
  - **Auto-sincronizaÃ§Ã£o inteligente**: Detecta evento ativo e envia telemetria automaticamente
  - **Indicador visual de bandeiras**: Cor de fundo muda conforme bandeira da sessÃ£o ativa
  - **SincronizaÃ§Ã£o de sessÃ£o**: Usa `sessionId` da sessÃ£o ativa do evento
  - Toggle de envio para cloud (`enableSendDataToCloud`)
- **NavegaÃ§Ã£o**: Transiciona para ActiveRaceScreen ao iniciar simulaÃ§Ã£o

### Active Race Screen

- **Arquivo**: `lib/features/screens/pilot/active_race_screen.dart`
- **ParÃ¢metros**: raceId, userId, raceName
- **Funcionalidade**:
  - GravaÃ§Ã£o GPS ao vivo via TelemetryService
  - Mapa Google com marcadores e polylines em tempo real
  - Marcadores customizados com cor do piloto
  - VisualizaÃ§Ã£o da rota dos checkpoints
  - **Auto-sincronizaÃ§Ã£o de telemetria**: Detecta automaticamente eventos ativos e sincroniza dados
  - **Indicador visual de bandeiras**: Cor de fundo muda dinamicamente baseado na bandeira da sessÃ£o (Verde, Amarela, Vermelha, Quadriculada)
  - **SincronizaÃ§Ã£o automÃ¡tica de sessÃ£o**: Monitora sessÃ£o ativa via Firestore e atualiza `sessionId` automaticamente
  - **Recuperacao de sessao ativa**: preload + rotina de recover para reduzir casos de tela presa em loading em links lentos (especialmente Android)
  - **Simulacao com controle manual**: botoes `START/STOP` disponiveis no Live Timer, sem perder auto-start por configuracao
  - **Timing local**: `Best/Previous/Current` vem do calculo local do dispositivo (ativo por padrao no piloto)
  - Cloud sync habilitado automaticamente quando evento ativo Ã© detectado
  - Carrega detalhes da corrida assincronamente

### Pilot Race Stats Screen

- **Arquivo**: `lib/features/screens/pilot/pilot_race_stats_screen.dart`
- **ParÃ¢metros**: raceId, userId, raceName, historySessionId (opcional)
- **Funcionalidade**:
  - Lista/seleÃ§Ã£o de voltas
  - Tempo da volta formatado (MM:SS.mmm)
  - Indicador de velocidade mÃ¡xima
  - GrÃ¡fico de perfil de velocidade (fl_chart - LineChart)
  - Tabela de intervalos entre checkpoints
  - EstatÃ­sticas comparativas: melhor volta, mÃ©dia, velocidade mÃ¡xima por volta
  - Detalhes expansÃ­veis por volta no grÃ¡fico
  - Suporta sessÃµes ao vivo e histÃ³ricas

---

## Telas do Admin

### Admin Dashboard (Refatorado - Estilo Orbits)

- **Arquivo**: `lib/features/screens/admin/admin_dashboard.dart`
- **Estrutura**: Interface baseada em abas para separar fluxos de trabalho:
  1.  **Setup (ConfiguraÃ§Ã£o)**:
      -   Monitoramento de Hardware/GPS.
      -   Gerenciamento de Pistas (Track Wizard).
  2.  **Registration (InscriÃ§Ã£o)**:
      -   Gerenciamento de Eventos e Pilotos.
      -   Lista de Eventos com aÃ§Ãµes para Criar/Editar.
  3.  **Timing (Cronometragem)**:
      -   Monitoramento de Corridas Ativas.
      -   Acesso ao Console de Controle de Corrida.

### Event Registration Screen

- **Arquivo**: `lib/features/screens/admin/event_registration_screen.dart`
- **Funcionalidade**: Gerenciamento detalhado de um evento de corrida.
- **Hierarquia**: Evento -> Grupos (Categorias) -> SessÃµes e Competidores.
- **Layout**: Responsivo (`LayoutBuilder`).
  -   **Desktop**: VisualizaÃ§Ã£o Master-Detail (Lista de Grupos Ã  esquerda, Detalhes Ã  direita).
  -   **Mobile**: NavegaÃ§Ã£o em lista (Lista de Grupos -> Tela de Detalhes).
-   **Abas de Detalhes**:
    -   **Running Order**: Lista de sessÃµes do grupo (Treino, ClassificaÃ§Ã£o, Corrida).
    -   **Competitors**: Lista de pilotos inscritos no grupo.

### Session Settings Screen

- **Arquivo**: `lib/features/screens/admin/session_settings_screen.dart`
- **Funcionalidade**: ConfiguraÃ§Ã£o detalhada de uma sessÃ£o.
- **Abas**:
  1.  **General**: Nome, Nome Curto, Tipo, Data/Hora.
  2.  **Timing**: MÃ©todo de Partida, Regras de Bandeira Vermelha.
  3.  **Auto Finish**: Modo de TÃ©rmino (Tempo, Voltas, etc.), DuraÃ§Ã£o.
  4.  **Qualification**: CritÃ©rios de ClassificaÃ§Ã£o.
  5.  **Timelines**: SeleÃ§Ã£o de linhas de controle/checkpoints.

### Competitor Settings Screen

- **Arquivo**: `lib/features/screens/admin/competitor_settings_screen.dart`
- **Funcionalidade**: Cadastro detalhado de competidores.
- **Abas**:
  1.  **Vehicle**: NÃºmero, Categoria, Registro do VeÃ­culo, Label (TLA).
  2.  **Competitor**: Nome, Sobrenome, Registro, **Link com UsuÃ¡rio do App**.
  3.  **Additional**: Campos personalizados (Patrocinador, Equipe, Cidade, etc.).

### Race Control Screen (Console)
- **Arquivo**: `lib/features/screens/admin/race_control_screen.dart`
- **Funcionalidade**: Painel de controle ao vivo da corrida, estilo "MyLaps Orbits".
- **Layout**: 3 PainÃ©is Verticais Interativos.
  1.  **Passings (Esquerda)**: Lista de passagens em tempo real nos checkpoints.
  2.  **Leaderboard (Centro)**: Tabela de tempos, posiÃ§Ãµes, gap e diff em tempo real.
  3.  **Visualizations (Direita)**: Mapa ao vivo (AdminMapView) e Lista de SessÃµes interativa.
- **Header e Barra de Controle**:
  -   **Header**: Exibe Nome do Evento, Nome do Grupo, e Nome da SessÃ£o (com Status).
  -   **SeleÃ§Ã£o de SessÃ£o**: Clique na lista de sessÃµes atualiza todas as visualizaÃ§Ãµes para a sessÃ£o selecionada.
  -   **BotÃµes de AÃ§Ã£o**: WARMUP (Roxa), START (Verde), SC (Amarela/Safety Car), RED (Vermelha), FINISH (Quadriculada), STOP.
  -   **SemÃ¢ntica de encerramento**: FINISH apenas muda a bandeira para quadriculada (sessÃ£o continua ativa). STOP finaliza a sessÃ£o.
  -   **ConfirmaÃ§Ã£o no STOP**: alerta confirma que a sessÃ£o serÃ¡ encerrada e os competidores deixarÃ£o de enviar GPS.
  -   **Info**: Exibe DuraÃ§Ã£o Restante, Voltas Totais e MÃ©todo de Partida.
  -   **Atalhos de Teclado**: F4 (WARMUP), F5 (Verde), F6 (Amarela), F7 (Vermelha), F8 (Quadriculada), F10 (InserÃ§Ã£o Manual).
- **Passings Panel (Detalhes)**:
  - **Filtragem por janela de tempo**: Exibe apenas passagens dentro do perÃ­odo `actualStartTime` a `actualEndTime` da sessÃ£o
  - **ResoluÃ§Ã£o dinÃ¢mica de nomes**: Busca nomes dos competidores em tempo real do evento (nÃ£o armazena nomes hardcoded)
  - **CÃ¡lculo automÃ¡tico de voltas**: NÃºmero da volta calculado dinamicamente baseado na contagem de passagens por competidor
  - **Cache de competidores**: PrÃ©-carrega nomes de todos os competidores do evento para performance
  - **AtualizaÃ§Ã£o em tempo real**: Nomes e voltas atualizam automaticamente quando admin modifica dados dos competidores
---

## ServiÃ§os (Camada de Dados)

### FirestoreService

- **Arquivo**: `lib/features/services/firestore_service.dart`
- **Responsabilidade**: Camada de acesso central ao Firestore
- **OperaÃ§Ãµes**:
  - **UsuÃ¡rios**: `getUserRole()`, `setUserRole()`, `updatePilotProfile()`, `getUserProfile()`
  - **Corridas**: `createRace()`, `updateRace()`, `deleteRace()`, `getOpenRaces()` (Stream)
  - **ParticipaÃ§Ã£o**: `joinRace()`
  - **Telemetria**: `updatePilotLocation()`, `sendTelemetryBatch()`, `getRaceLocations()` (Stream)
  - **SessÃµes/Voltas**: `getLaps()`, `getSessionLaps()`, `getHistorySessions()`, `getHistorySessionLaps()`
  - **Eventos**: `getActiveEventForTrack()`, `getEventActiveSessionStream()` (Stream)
  - **Feature flags runtime**: `getSimulationRuntimeConfig()`, `getLocalTimingRuntimeConfig()`
  - **Competidores**: `getCompetitors()`, `getCompetitorByUid()`, `getCompetitorsStream()` (Stream)
  - **Passagens**: `getPassingsStream()` (Stream com filtragem por janela de tempo)
  - **Limpeza**: `clearRaceParticipants()`, `clearRaceParticipantsLaps()`, `archiveCurrentLaps()`

### TelemetryService

- **Arquivo**: `lib/features/services/telemetry_service.dart`
- **Extends**: `ChangeNotifier`
- **Responsabilidade**: Coleta e sincronizaÃ§Ã£o de dados GPS
- **Funcionalidades**:
  - Stream GPS via `geolocator` (intervalo de 50ms)
  - Persistencia local offline-first em SQLite para `telemetry` e `local_lap_closures`
  - Sync por lote a cada 5s a partir das filas locais (nao apenas buffer em memoria)
  - Sincronizacao idempotente de closures por `closure_id`
  - Gerenciamento de wakelock (tela ligada durante gravaÃ§Ã£o)
  - CÃ¡lculo de frequÃªncia (Hz)
  - GeraÃ§Ã£o de Session ID (formato: `dd-MM-yyyy HH:mm:ss`)
  - DetecÃ§Ã£o de checkpoints e gerenciamento de voltas local
  - Simulacao de rota com speed configuravel e sincronizacao por lote
  - Motor de timing local com cruzamento de linha virtual (interpolacao + fallback por proximidade)
  - Reconstrucao de linhas efetivas a partir de `checkpoints + timelines`
  - Reenvio automatico de filas pendentes apos reconexao/reabertura do app
- **MÃ©todos principais**: `startRecording()`, `stopRecording()`, `startSimulation()`, `stopSimulation()`, `setCheckpoints()`, `setTimelines()`, `setLocalTimingEnabled()`
- **RecuperaÃ§Ã£o de erros**: filas locais permanecem pendentes e sao reenviadas em tentativas futuras

### LocalDatabaseService

- **Arquivo**: `lib/features/services/local_database_service.dart`
- **Responsabilidade**: Cache SQLite offline para telemetria e fechamento local de voltas
- **PadrÃ£o**: Singleton
- **Database**: `speed_data_telemetry.db`
- **Tabelas**:
  - `telemetry` (id, raceId, eventId, uid, session, lat, lng, speed, heading, altitude, timestamp, synced)
  - `local_lap_closures` (id, raceId, eventId, uid, session, closureId, payloadJson, sfCrossedAtMs, capturedAtMs, synced)
- **Indices**:
  - `idx_telemetry_sync` para leitura de pontos pendentes por sessao
  - `idx_local_lap_closure_unique` (UNIQUE em `closureId`) para idempotencia local
  - `idx_local_lap_closure_sync` para leitura eficiente da fila de closures
- **MÃ©todos**: `insertPoint()`, `getUnsyncedPoints()`, `markAsSynced()`, `insertLapClosure()`, `getUnsyncedLapClosures()`, `markLapClosuresAsSynced()`, `markLapClosuresAsSyncedByClosureIds()`, `clearSynced()`

### RouteService

- **Arquivo**: `lib/features/services/route_service.dart`
- **Responsabilidade**: CÃ¡lculo de rotas via Google Directions API
- **MÃ©todo**: `getRouteBetweenPoints(List<LatLng>)` - retorna coordenadas detalhadas da rota

---

## Fluxo de Dados Principal

```
GPS Hardware (Geolocator, 50ms)
    |
    v
TelemetryService - calculo local + filas locais
    |
    v
SQLite (telemetry + local_lap_closures)
    |
    v
Timer periÃ³dico (5 segundos) / tentativa sob demanda
    |
    v
FirestoreService.sendTelemetryBatch(points + localLapClosures)
    |
    v
Firebase Cloud Function (ingestTelemetry)
    |
    +---> Materializa laps a partir de localLapClosures (source=local_closure)
    |
    +---> Modo estrito: nao fecha/abre volta via pontos brutos no start/finish
    |
    +---> Escrita em passings/crossings/laps/summary por sessao
    |
    +---> Pub/Sub para processamento assÃ­ncrono
    |
    v
Firestore Database (races/participants/sessions/laps/passings)
    |
    v
Firestore Streams (snapshots em tempo real)
    |
    v
UI StreamBuilders (atualizaÃ§Ã£o automÃ¡tica)
    |
    +---> PassingsPanel: ResoluÃ§Ã£o dinÃ¢mica de nomes via getCompetitorByUid()
    |
    +---> PassingsPanel: CÃ¡lculo automÃ¡tico de nÃºmero de voltas
```

Observacao (Fases 1 e 2 local timing/offline-first):
- O Live Timer opera em caminho local no dispositivo (habilitado por padrao na tela do piloto).
- O cronometro usa cruzamento de linhas virtuais no app para `best/previous/current`.
- Fechamentos locais de volta (`localLapClosures`) ficam persistidos no SQLite e sincronizam depois.
- O backend prioriza o calculo local (strict mode) para evitar volta fantasma no start/finish.

### Processamento em Background

- **Android**: Foreground Service com notificaÃ§Ã£o ("Race Recording - Telemetry is being captured")
- **Wakelock**: Impede que o dispositivo durma durante gravaÃ§Ã£o
- **Offline**: SQLite como backup local; sync automÃ¡tico quando conectividade restaurada

---

## Atualizacoes Recentes (Implementado)

### Piloto - Available Races / Eventos
- **Card de evento ativo**: exibe evento registrado no periodo atual, nome do evento e pista. Quando ha sessao ativa, card fica verde (bandeira) e mostra CTA para abrir Live Timer.
- **CTA destacado**: botao "GO TO LIVE TIMER" com alto contraste (texto na cor da bandeira, fundo claro).
- **Texto em ingles**: mensagens do card e da lista de pistas em ingles.
- **Proxima sessao**: mostra horario previsto de inicio (HH:mm).
- **Practice tracks bloqueadas**: quando ha sessao ativa para o usuario, a lista de pistas de treino fica desabilitada e com aviso explicativo.
- **Eventos (area nova)**: tela de eventos para piloto com "My events" e "Other events" e cronograma por evento em ordem cronologica.
- **Lap Times por sessao (eventos)**: no fluxo `Eventos -> Sessao`, o app abre Lap Times direto na sessao selecionada.
- **Sessao fixa no fluxo de eventos**: nesse contexto o seletor de sessao fica travado e mostra apenas o nome da sessao (sem opcao `Legacy (no session)`).
- **Layout mobile compacto em Lap Times**: filtros ocupam menos espaco e ficam recolhiveis por padrao para priorizar a tabela de voltas.

### Piloto - Live Timer
- **Tres modos**: Simple (Best/Previous/Current), Classic (Current + Track Chart), Gauge (Gauge + Current).
- **Status da sessao**: indicador reflete bandeira (verde/amarela/vermelha/quadriculada).
- **Borda por bandeira**: borda do Live Timer acompanha a bandeira da sessao.
- **Nome da sessao**: exibido no AppBar; nome do evento em label discreto.
- **Best/Previous/Current**: calculados localmente no dispositivo (modo local ativo por padrao na tela do piloto).
- **Current fluido**: cronometro atualizado em intervalos curtos para evitar saltos.
- **Simulacao (modo desenvolvimento)**: inicia automaticamente quando habilitada para o usuario e ha sessao ativa, com botoes `START/STOP` para pausa e retomada manual.
- **Retorno para Live Timer**: ao reabrir a tela, a sessÃ£o ativa Ã© prÃ©-carregada para reduzir tempo de espera.
- **Sem START/FINISH de corrida**: botoes manuais de controle de bandeira/sessao permanecem somente no admin; no piloto ha apenas controle de simulacao.
- **Warmup (bandeira)**: bandeira roxa WARMUP exibida no status e nas cores do Live Timer.
- **Indicador de modo local**: rodape informa quando o timing local esta ativo para o usuario.

### Telemetria (Piloto)
- **Envio automatico em sessao ativa**: quando ha sessao ativa, GPS fica capturando mesmo fora do Live Timer.
- **Simulacao persistente**: simulacao continua mesmo ao sair da tela Live Timer.
- **Bloqueio de envio real durante simulacao**: enquanto simula, nao envia dados reais.
- **Parada no STOP (Admin)**: quando o admin finaliza com STOP, os competidores param de capturar/enviar GPS.
- **TelemetryService singleton**: centraliza estado e evita duplicidade de streams.
- **Config de simulacao por usuario (Firestore)**:
  - Global: `app_config/simulation` com `enabled_default`, `auto_start_default`, `default_speed_mps`.
  - Override por usuario: `simulation_testers/{email_normalizado}` com `enabled`, `auto_start`, `speed_mps`, `valid_from`, `valid_until`.
  - O app resolve configuracao por e-mail autenticado; se habilitado, o modo simulacao inicia automaticamente quando a sessao ativa.
- **Config de timing local por usuario (Firestore)**:
  - Global: `app_config/local_timing` com `enabled_default`.
  - Override por usuario: `local_timing_testers/{email_normalizado}` com `enabled`, `valid_from`, `valid_until`.
  - Mantido por compatibilidade administrativa; no piloto atual o calculo local esta ativo por padrao.
- **Cruzamento local estilo RaceChrono (Fase 1)**:
  - Linhas virtuais sao geradas com largura padrao de 50 m.
  - Cruzamento usa interpolacao geometrica de segmento com fallback por proximidade e gate direcional.
  - `best_lap` e `optimal/current` consideram apenas voltas validas (tempo > 0 e acima do minimo da sessao).
- **Offline-first (Fase 2)**:
  - Pontos GPS e `local_lap_closures` sao persistidos primeiro no SQLite.
  - O sync envia lotes por sessao e marca como sincronizado somente apos sucesso.
  - Reabertura do app continua sincronizando pendencias antigas automaticamente.
- **Nuvem em modo estrito local-priority**:
  - `ingestTelemetry` materializa laps com base em `localLapClosures`.
  - Fechamento/abertura de volta por ponto bruto em start/finish fica bloqueado para evitar volta fantasma.

### Admin - Timing / Results / Passings / Track Chart
- **Results**: mostra resultado da sessao (treino/qualificacao por melhor tempo valido; corrida por numero de voltas).
- **Best/Last/Total/Laps**: calculados por passings; Total = tempo entre primeira e ultima passagem.
- **Best mostra numero da volta**: formato "tempo (volta)".
- **Min lap time**: voltas abaixo do minimo sao invalidas para resultado.
- **Passings enriquecido**: painel exibe `sector_time`, `split_time` e `trap_speed` quando disponiveis.
- **Passings com cores/icone**:
  - Roxo = melhor volta geral, Verde = melhor volta pessoal.
  - Vermelho = violacao de tempo minimo.
  - Icone relogio = manual; icone lampada/pin = fotocelula sem transponder.
  - X vermelha = deletada (linha cinza, texto vermelho).
  - Simbolo de proibido = volta invalidada (conta volta, nao recorde).
- **Passings ordenado por time**: mistura bandeiras e competidores por timestamp.
- **Track Chart admin**: posicoes atualizam direto (sem interpolacao) para evitar bolinha fora da pista.
- **Warmup (bandeira)**: nova bandeira roxa no controle de corrida; ao acionar, inicia a sessao se estiver agendada e registra `flag_warmup` nas passagens.
- **STOP vs FINISH**: FINISH nao encerra sessao; STOP encerra sessao e interrompe coleta/envio de GPS dos competidores.
- **Lap Times (admin)**: no Race Control, o admin pode abrir Lap Times da sessao selecionada e escolher qualquer participante para visualizar os dados da sessao.

---

## Estrutura do Firestore

```
/users/{uid}
  â”œâ”€â”€ role: "pilot" | "admin" | "root"
  â”œâ”€â”€ name: string
  â””â”€â”€ color: number (ARGB)

/app_config/simulation
  â”œâ”€â”€ enabled_default: bool
  â”œâ”€â”€ auto_start_default: bool
  â””â”€â”€ default_speed_mps: number

/simulation_testers/{email_normalizado}
  â”œâ”€â”€ enabled: bool
  â”œâ”€â”€ auto_start: bool
  â”œâ”€â”€ speed_mps: number
  â”œâ”€â”€ valid_from: timestamp?
  â””â”€â”€ valid_until: timestamp?

/app_config/local_timing
  â””â”€â”€ enabled_default: bool

/local_timing_testers/{email_normalizado}
  â”œâ”€â”€ enabled: bool
  â”œâ”€â”€ valid_from: timestamp?
  â””â”€â”€ valid_until: timestamp?

/races/{raceId}
  â”œâ”€â”€ name: string
  â”œâ”€â”€ creator_id: string (uid)
  â”œâ”€â”€ created_at: timestamp
  â”œâ”€â”€ status: "open" | "closed"
  â”œâ”€â”€ checkpoints: [{lat, lng}, ...]
  â”œâ”€â”€ route_path: [{lat, lng}, ...]
  â”‚
  â”œâ”€â”€ /local_lap_closures/{closureId}
  â”‚   â”œâ”€â”€ closure_id: string
  â”‚   â”œâ”€â”€ participant_uid: string
  â”‚   â”œâ”€â”€ session_id: string
  â”‚   â”œâ”€â”€ lap_number: number
  â”‚   â”œâ”€â”€ sf_crossed_at_ms: number
  â”‚   â”œâ”€â”€ post_sf_point: map
  â”‚   â””â”€â”€ source: "local_timing_app"
  â”‚
  â”œâ”€â”€ /passings/{passingId}
  â”‚   â”œâ”€â”€ participant_uid: string (uid do competidor)
  â”‚   â”œâ”€â”€ lap_number: number (calculado pela Cloud Function)
  â”‚   â”œâ”€â”€ lap_time: number (milissegundos)
  â”‚   â”œâ”€â”€ timestamp: timestamp (Firestore Timestamp)
  â”‚   â”œâ”€â”€ session_id: string
  â”‚   â”œâ”€â”€ checkpoint_index: number (0 = linha de chegada)
  â”‚   â”œâ”€â”€ flags: array (best_lap, personal_best, invalid, etc.)
  â”‚   â”œâ”€â”€ sector_time: number | null
  â”‚   â”œâ”€â”€ split_time: number | null
  â”‚   â””â”€â”€ trap_speed: number | null
  â”‚
  â””â”€â”€ /participants/{uid}
      â”œâ”€â”€ uid: string
      â”œâ”€â”€ display_name: string
      â”œâ”€â”€ color: string (numeric)
      â”œâ”€â”€ joined_at: timestamp
      â”œâ”€â”€ current: {lat, lng, speed, heading, timestamp, last_updated}
      â”‚
      â”œâ”€â”€ /sessions/{sessionId}
      â”‚   â””â”€â”€ /laps/{lapId}
      â”‚       â””â”€â”€ {dados da volta}
      â”‚
      â”œâ”€â”€ /history_sessions/{sessionId}
      â”‚   â”œâ”€â”€ archived_at: timestamp
      â”‚   â””â”€â”€ /laps/{lapId}
      â”‚       â””â”€â”€ {dados da volta}
      â”‚
      â””â”€â”€ /laps/{lapId}
          â””â”€â”€ {dados da volta}
```

---

## Contrato de Dados - Lap Times

### crossings (por sessao)
- Caminho: `races/{raceId}/participants/{uid}/sessions/{sessionId}/crossings/{crossingId}`
- Espelho opcional por evento/sessao: `events/{eventId}/sessions/{sessionId}/participants/{uid}/crossings/{crossingId}`
- Obrigatorios: `lap_number`, `checkpoint_index`, `crossed_at_ms`, `speed_mps`, `lat`, `lng`, `method`, `distance_to_checkpoint_m`, `confidence`, `created_at`
- `method` aceito: `interpolated`, `nearest_point`, `line_interpolation`, `nearest_point_fallback` (dependendo do pipeline/backend ou modo local)
- Opcionais/derivados: `sector_time_ms` (delta desde checkpoint anterior), `split_time_ms` (delta desde cp_0), `backfilled_from_passings` (quando reconstruido)

### laps (por sessao)
- Caminho: `races/{raceId}/participants/{uid}/sessions/{sessionId}/laps/{lapId}`
- Espelho opcional por evento/sessao: `events/{eventId}/sessions/{sessionId}/participants/{uid}/laps/{lapId}`
- Obrigatorios: `number`, `lap_start_ms`, `lap_end_ms`, `total_lap_time_ms`, `valid`, `created_at`
- Recomendados: `invalid_reasons` (array), `splits_ms` (lista de deltas para cada checkpoint), `sectors_ms` (intervalos entre checkpoints), `trap_speeds_mps` (velocidade no crossing), `speed_stats` (`min_mps`, `max_mps`, `avg_mps`), `distance_m`
- Compatibilidade: o mesmo `lapId` tambem e salvo em `participants/{uid}/laps/{lapId}` para telas legadas.

### analysis/summary (por sessao)
- Caminho: `races/{raceId}/participants/{uid}/sessions/{sessionId}/analysis/summary`
- Espelho opcional por evento/sessao: `events/{eventId}/sessions/{sessionId}/analysis/summary`
- Campos: `best_lap_ms`, `optimal_lap_ms`, `best_sectors_ms` (array), `valid_laps_count`, `total_laps_count`, `updated_at`
- Logica: `best_lap_ms` considera apenas voltas validas; `optimal_lap_ms` e a soma dos melhores setores acumulados em `best_sectors_ms`.

### state/current (controle incremental)
- Caminho: `races/{raceId}/participants/{uid}/sessions/{sessionId}/state/current`
- Campos de sequenciamento: `lap_number`, `lap_start_ms`, `last_checkpoint_index`, `last_crossed_at_ms`, `checkpoint_times` (mapa cp -> timestamp), `checkpoint_speeds` (mapa cp -> speed)
- Campos de posicao atual (merge): `current.lat`, `current.lng`, `current.speed`, `current.heading`, `current.altitude`, `current.timestamp`, `current.last_updated`
- Uso: evita duplicidade de checkpoints, permite calcular setor/split incremental e abre nova volta ao detectar `cp_0`.

### local_lap_closures (fila local sincronizada)
- Origem: app piloto (`TelemetryService`) apos detectar fechamento de volta local.
- Envio: no payload de `ingestTelemetry` como `localLapClosures`.
- Persistencia local no app: SQLite `local_lap_closures` com `closureId` unico (idempotencia).
- Persistencia em nuvem (auditoria): `races/{raceId}/local_lap_closures/{closureId}` e, quando aplicavel, `events/{eventId}/sessions/{sessionId}/local_lap_closures/{closureId}`.
- Campos chave: `closure_id`, `session_id`, `lap_number`, `lap_time_ms`, `sf_crossed_at_ms`, `sf_crossing`, `post_sf_point`, `local_timing_min_lap_ms`.

### BigQuery
- Dataset `telemetry.raw_points` recebe cada ponto com `raceId`, `uid`, `sessionId` e campos brutos de GPS (lat, lng, speed, heading, altitude, timestamp).
- Futuras tabelas podem consumir `laps` e `crossings` para analises agregadas sem impactar o fluxo online.

### Lap Times (UI piloto/admin)
- Tela base: `lib/features/screens/pilot/lap_times_screen.dart`
- Acesso (piloto):
  - Dashboard: `Stats -> Lap Times (dados por sessao)`.
  - Eventos: `Eventos -> selecionar evento -> selecionar sessao` (abre direto com sessao fixa).
- Acesso (admin):
  - Race Control: acao `Lap Times (All participants)` abre lista de participantes da sessao.
  - Tela de apoio: `lib/features/screens/admin/admin_session_lap_times_screen.dart`.
- Modos implementados:
  - `Sectors`: tabela por volta com linha `OPT`, comparacao por cor contra volta de referencia (melhor valida)
  - `Splits`: tabela por checkpoint acumulado (`splits_ms`) com comparacao por cor
  - `Trap Speeds`: tabela de velocidades por trap (`trap_speeds_mps`) com comparacao por referencia
  - `High/Low`: tabela com `low/high/avg/range` por volta usando `speed_stats` (ou fallback para `trap_speeds_mps`)
  - `Information`: painel consolidado com `best_lap`, `optimal_lap`, contagens de voltas validas/total e snapshot de crossings
- Contexto de sessao:
  - Em contexto de evento/sessao a tela bloqueia fallback legado (sem `Legacy`) para evitar mistura de fontes.
  - Sessao pode ser travada por parametro (`lockSessionSelection`) e exibida como label fixa.
- UX mobile:
  - Em telas estreitas, os filtros ficam em painel recolhivel (`Filters`) por padrao.
  - Header e controles usam paddings compactos para ampliar a area util da tabela.
- Regra de validade na UI: referencia e resumo derivado usam somente voltas validas (`valid=true` e `total_lap_time_ms > 0`).

### Local Timing (Fase 1 + Fase 2 offline-first)
- Config runtime:
  - Global: `app_config/local_timing.enabled_default`
  - Override: `local_timing_testers/{email_normalizado}`
- Comportamento:
  - O Live Timer usa `TelemetryService` para calcular `best/previous/current` localmente.
  - Na implementacao atual do piloto, o modo local esta forçado como ativo por padrao.
  - O processamento usa linhas virtuais baseadas em `checkpoints` + `timelines` da sessao.
  - Largura padrao de linha virtual: 50 m.
  - Fechamento de volta respeita `min_lap_time_seconds` da sessao.
  - Fase 2: fechamento de volta local entra em fila SQLite (`local_lap_closures`) e sincroniza de forma idempotente.
  - Backend em strict mode: fechamento/abertura de volta no start/finish nao e feito por ponto bruto, apenas por `localLapClosures`.
- Objetivo da fase: reduzir latencia e permitir operacao robusta sem conectividade.

### Backfill legada -> sessao (job administrativo)
- Function callable: `backfillSessionAnalytics`
- Objetivo: reconstruir `sessions/{sessionId}/crossings`, `sessions/{sessionId}/laps` e `analysis/summary` a partir de passings legados.
- Entrada minima: `raceId`, `sessionId` (opcional `eventId`, `participantLimit`, `minLapTimeSeconds`).
- Seguranca: execucao restrita a usuarios admin/root.
- Resultado: retorna contadores (`participantsUpdated`, `lapsRebuilt`, `crossingsRebuilt`) para auditoria.

---

## NavegaÃ§Ã£o (GoRouter)

### Rotas definidas

| Rota | Widget | DescriÃ§Ã£o |
|------|--------|-----------|
| `/` | Home (ou Login se deslogado) | Rota inicial |
| `/login` | LoginWidget | AutenticaÃ§Ã£o |
| `/signUp` | SignUpWidget | Cadastro |
| `/pilotProfileSetup` | PilotProfileSetupWidget | Setup de perfil do piloto |
| `/homePage` | HomePageWidget | Roteador principal |
| `/landingPage` | LandingPageWidget | SeleÃ§Ã£o de papel |

### NavegaÃ§Ã£o interna (Navigator.push)

```
HomePageWidget
  â”œâ”€â”€ Admin/Root â†’ AdminDashboard
  â”‚     â”œâ”€â”€ â†’ CreateRaceScreen (nova corrida)
  â”‚     â”œâ”€â”€ â†’ CreateRaceScreen (editar, com params)
  â”‚     â””â”€â”€ â†’ AdminMapView (monitorar ao vivo)
  â”‚
  â””â”€â”€ Pilot â†’ PilotDashboard
        â”œâ”€â”€ â†’ GpsTestScreen â†’ ActiveRaceScreen
        â””â”€â”€ â†’ PilotRaceStatsScreen (bottom sheet)
```

---

## Stack TecnolÃ³gica

| Camada | Tecnologia |
|--------|------------|
| **Frontend** | Flutter (Dart) + FlutterFlow |
| **AutenticaÃ§Ã£o** | Firebase Auth (Email, Google, Apple, GitHub) |
| **Banco de Dados** | Cloud Firestore (primÃ¡rio) + SQLite (backup offline) |
| **Backend** | Google Cloud Functions + Pub/Sub |
| **Mapas/LocalizaÃ§Ã£o** | Google Maps Flutter + Geolocator |
| **Roteamento** | GoRouter |
| **Estado** | Provider + ChangeNotifier + StreamBuilder |
| **GrÃ¡ficos** | fl_chart |
| **Outros** | wakelock_plus, rxdart, intl, google_fonts |

---

## Modelos de Dados

### UserRole (Enum)

- **Arquivo**: `lib/features/models/user_role.dart`
- **Valores**: `pilot`, `admin`, `root`, `unknown`
- **MÃ©todos**: `fromString()`, `toStringValue()`
- **Suporte bilÃ­ngue**: "pilot"/"piloto", "admin"/"administrador"

### PilotStats (Classe)

- **Arquivo**: `lib/features/screens/admin/widgets/leaderboard_panel.dart`
- **Campos**: `uid`, `displayName`, `averageLapTime`, `bestLapTime`, `completedLaps`, `currentLapNumber`, `currentPoints`, `intervalStrings`

### SpeedDataFirebaseUser (Auth)

- **Arquivo**: `lib/auth/firebase_auth/firebase_user_provider.dart`
- **Campos**: `user` (Firebase User), `loggedIn`, `authUserInfo`




