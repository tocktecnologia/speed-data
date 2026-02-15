# Speed Data - Especificações do Aplicativo

Plataforma de telemetria e rastreamento GPS em tempo real para corridas (drones/karts/automobilismo).
Construído com **Flutter + FlutterFlow**, usando **Firebase** (Auth, Firestore, Cloud Functions) como backend.

> Este documento é atualizado sempre que houver mudanças ou adições de funcionalidades.

---

## Sumário

- [Visão Geral](#visão-geral)
- [Fluxo de Autenticação](#fluxo-de-autenticação)
- [Tela Principal](#tela-principal-roteador)
- [Telas do Piloto](#telas-do-piloto)
- [Telas do Admin](#telas-do-admin)
- [Serviços](#serviços-camada-de-dados)
- [Fluxo de Dados](#fluxo-de-dados-principal)
- [Estrutura do Firestore](#estrutura-do-firestore)
- [Navegação](#navegação-gorouter)
- [Stack Tecnológica](#stack-tecnológica)

---

## Visão Geral

**Speed Data** é um sistema multi-papel com dois perfis principais:

- **Piloto**: participa de corridas, grava telemetria GPS, analisa desempenho
- **Admin**: cria pistas, monitora corridas ao vivo, visualiza leaderboard

### Fluxo Principal

1. Admin cria corrida com checkpoints no mapa
2. Piloto entra na corrida e inicia gravação GPS
3. Telemetria é capturada a cada 50ms e sincronizada a cada 5s para Cloud Functions
4. Cloud Function processa dados, detecta voltas e calcula estatísticas
5. Admin monitora posições ao vivo e leaderboard
6. Piloto analisa desempenho pós-corrida (gráficos, tempos, intervalos)

---

## Fluxo de Autenticação

### Landing Page

- **Arquivo**: `lib/pages/landing_page_widget.dart`
- **Rota**: `/landingPage`
- **Funcionalidade**: Tela inicial com logo "SPEED DATA". Dois botões de seleção de papel: PILOTO e ADMIN. Link "Already have account? Login"
- **Navegação**: Redireciona para Sign Up (com papel) ou Login

### Login

- **Arquivo**: `lib/login/login_widget.dart`
- **Rota**: `/login`
- **Funcionalidade**:
  - Campos: email, senha (com toggle de visibilidade)
  - Dropdown de seleção de papel (Pilot/Admin)
  - Botão "Entrar pelo Google" (Google OAuth)
  - Botão "Entrar" (email/senha)
  - Link para cadastro
- **Layout**: Responsivo (variação mobile e desktop)
- **Navegação**: Login bem-sucedido vai para HomePage

### Sign Up

- **Arquivo**: `lib/sign_up/sign_up_widget.dart`
- **Rota**: `/signUp`
- **Funcionalidade**:
  - Campos: email, senha, confirmação de senha
  - Dropdown de papel (Pilot/Admin)
  - Validação: senhas devem coincidir
  - Criação de conta via `authManager.createAccountWithEmail()`
- **Navegação**: Piloto vai para Pilot Profile Setup; Admin vai para HomePage

### Pilot Profile Setup

- **Arquivo**: `lib/sign_up/pilot_profile_setup_widget.dart`
- **Rota**: `/pilotProfileSetup`
- **Funcionalidade**:
  - Campo: nome do piloto (pré-preenchido com displayName)
  - Paleta de 21 cores para escolha da cor do piloto
  - Cor selecionada exibe checkmark e efeito de brilho
  - Salva perfil no Firestore via `FirestoreService.updatePilotProfile()`
- **Navegação**: Vai para HomePage após salvar

---

## Tela Principal (Roteador)

### Home Page

- **Arquivo**: `lib/pages/home_page/home_page_widget.dart`
- **Rota**: `/homePage`
- **Funcionalidade**:
  - Busca o papel do usuário no Firestore via `FirestoreService.getUserRole()`
  - Redireciona com base no papel:
    - Admin/Root → AdminDashboard
    - Pilot → PilotDashboard
    - Sem papel → UI de seleção de papel
  - Loading spinner enquanto determina o papel
  - AppBar com botão de logout

---

## Telas do Piloto

### Pilot Dashboard

- **Arquivo**: `lib/features/screens/pilot/pilot_dashboard.dart`
- **Funcionalidade**:
  - Lista de corridas abertas (stream em tempo real via `getOpenRaces()`)
  - Cada card de corrida exibe: nome, status ("Open for registration"), botões de ação
  - Botão "Test GPS": entra na corrida e navega para GpsTestScreen
  - Botão "Stats": exibe estatísticas via bottom sheet
  - Navigation drawer com info do usuário e logout
- **Dados exibidos**: Lista de corridas (atualização em tempo real)

### GPS Test Screen

- **Arquivo**: `lib/features/screens/pilot/gps_test_screen.dart`
- **Parâmetros**: raceId, userId, raceName
- **Funcionalidade**:
  - Mapa Google com checkpoints marcados (A, B, C...)
  - Visualização da rota com polyline
  - Controles de simulação:
    - Slider de velocidade (m/s ajustável, padrão 40 m/s)
    - Botões Start/Stop
  - Painel de telemetria: velocidade atual, Hz, coordenadas
  - Rota carregada do Firestore ou calculada dos checkpoints
  - Sistema de buffer/batch para dados de telemetria (sync a cada 5s)
  - **Auto-sincronização inteligente**: Detecta evento ativo e envia telemetria automaticamente
  - **Indicador visual de bandeiras**: Cor de fundo muda conforme bandeira da sessão ativa
  - **Sincronização de sessão**: Usa `sessionId` da sessão ativa do evento
  - Toggle de envio para cloud (`enableSendDataToCloud`)
- **Navegação**: Transiciona para ActiveRaceScreen ao iniciar simulação

### Active Race Screen

- **Arquivo**: `lib/features/screens/pilot/active_race_screen.dart`
- **Parâmetros**: raceId, userId, raceName
- **Funcionalidade**:
  - Gravação GPS ao vivo via TelemetryService
  - Mapa Google com marcadores e polylines em tempo real
  - Marcadores customizados com cor do piloto
  - Visualização da rota dos checkpoints
  - **Auto-sincronização de telemetria**: Detecta automaticamente eventos ativos e sincroniza dados
  - **Indicador visual de bandeiras**: Cor de fundo muda dinamicamente baseado na bandeira da sessão (Verde, Amarela, Vermelha, Quadriculada)
  - **Sincronização automática de sessão**: Monitora sessão ativa via Firestore e atualiza `sessionId` automaticamente
  - Cloud sync habilitado automaticamente quando evento ativo é detectado
  - Carrega detalhes da corrida assincronamente

### Pilot Race Stats Screen

- **Arquivo**: `lib/features/screens/pilot/pilot_race_stats_screen.dart`
- **Parâmetros**: raceId, userId, raceName, historySessionId (opcional)
- **Funcionalidade**:
  - Lista/seleção de voltas
  - Tempo da volta formatado (MM:SS.mmm)
  - Indicador de velocidade máxima
  - Gráfico de perfil de velocidade (fl_chart - LineChart)
  - Tabela de intervalos entre checkpoints
  - Estatísticas comparativas: melhor volta, média, velocidade máxima por volta
  - Detalhes expansíveis por volta no gráfico
  - Suporta sessões ao vivo e históricas

---

## Telas do Admin

### Admin Dashboard (Refatorado - Estilo Orbits)

- **Arquivo**: `lib/features/screens/admin/admin_dashboard.dart`
- **Estrutura**: Interface baseada em abas para separar fluxos de trabalho:
  1.  **Setup (Configuração)**:
      -   Monitoramento de Hardware/GPS.
      -   Gerenciamento de Pistas (Track Wizard).
  2.  **Registration (Inscrição)**:
      -   Gerenciamento de Eventos e Pilotos.
      -   Lista de Eventos com ações para Criar/Editar.
  3.  **Timing (Cronometragem)**:
      -   Monitoramento de Corridas Ativas.
      -   Acesso ao Console de Controle de Corrida.

### Event Registration Screen

- **Arquivo**: `lib/features/screens/admin/event_registration_screen.dart`
- **Funcionalidade**: Gerenciamento detalhado de um evento de corrida.
- **Hierarquia**: Evento -> Grupos (Categorias) -> Sessões e Competidores.
- **Layout**: Responsivo (`LayoutBuilder`).
  -   **Desktop**: Visualização Master-Detail (Lista de Grupos à esquerda, Detalhes à direita).
  -   **Mobile**: Navegação em lista (Lista de Grupos -> Tela de Detalhes).
-   **Abas de Detalhes**:
    -   **Running Order**: Lista de sessões do grupo (Treino, Classificação, Corrida).
    -   **Competitors**: Lista de pilotos inscritos no grupo.

### Session Settings Screen

- **Arquivo**: `lib/features/screens/admin/session_settings_screen.dart`
- **Funcionalidade**: Configuração detalhada de uma sessão.
- **Abas**:
  1.  **General**: Nome, Nome Curto, Tipo, Data/Hora.
  2.  **Timing**: Método de Partida, Regras de Bandeira Vermelha.
  3.  **Auto Finish**: Modo de Término (Tempo, Voltas, etc.), Duração.
  4.  **Qualification**: Critérios de Classificação.
  5.  **Timelines**: Seleção de linhas de controle/checkpoints.

### Competitor Settings Screen

- **Arquivo**: `lib/features/screens/admin/competitor_settings_screen.dart`
- **Funcionalidade**: Cadastro detalhado de competidores.
- **Abas**:
  1.  **Vehicle**: Número, Categoria, Registro do Veículo, Label (TLA).
  2.  **Competitor**: Nome, Sobrenome, Registro, **Link com Usuário do App**.
  3.  **Additional**: Campos personalizados (Patrocinador, Equipe, Cidade, etc.).

### Race Control Screen (Console)
- **Arquivo**: `lib/features/screens/admin/race_control_screen.dart`
- **Funcionalidade**: Painel de controle ao vivo da corrida, estilo "MyLaps Orbits".
- **Layout**: 3 Painéis Verticais Interativos.
  1.  **Passings (Esquerda)**: Lista de passagens em tempo real nos checkpoints.
  2.  **Leaderboard (Centro)**: Tabela de tempos, posições, gap e diff em tempo real.
  3.  **Visualizations (Direita)**: Mapa ao vivo (AdminMapView) e Lista de Sessões interativa.
- **Header e Barra de Controle**:
  -   **Header**: Exibe Nome do Evento, Nome do Grupo, e Nome da Sessão (com Status).
  -   **Seleção de Sessão**: Clique na lista de sessões atualiza todas as visualizações para a sessão selecionada.
  -   **Botões de Ação**: WARMUP (Roxa), START (Verde), SC (Amarela/Safety Car), RED (Vermelha), FINISH (Quadriculada), STOP.
  -   **Semântica de encerramento**: FINISH apenas muda a bandeira para quadriculada (sessão continua ativa). STOP finaliza a sessão.
  -   **Confirmação no STOP**: alerta confirma que a sessão será encerrada e os competidores deixarão de enviar GPS.
  -   **Info**: Exibe Duração Restante, Voltas Totais e Método de Partida.
  -   **Atalhos de Teclado**: F4 (WARMUP), F5 (Verde), F6 (Amarela), F7 (Vermelha), F8 (Quadriculada), F10 (Inserção Manual).
- **Passings Panel (Detalhes)**:
  - **Filtragem por janela de tempo**: Exibe apenas passagens dentro do período `actualStartTime` a `actualEndTime` da sessão
  - **Resolução dinâmica de nomes**: Busca nomes dos competidores em tempo real do evento (não armazena nomes hardcoded)
  - **Cálculo automático de voltas**: Número da volta calculado dinamicamente baseado na contagem de passagens por competidor
  - **Cache de competidores**: Pré-carrega nomes de todos os competidores do evento para performance
  - **Atualização em tempo real**: Nomes e voltas atualizam automaticamente quando admin modifica dados dos competidores
---

## Serviços (Camada de Dados)

### FirestoreService

- **Arquivo**: `lib/features/services/firestore_service.dart`
- **Responsabilidade**: Camada de acesso central ao Firestore
- **Operações**:
  - **Usuários**: `getUserRole()`, `setUserRole()`, `updatePilotProfile()`, `getUserProfile()`
  - **Corridas**: `createRace()`, `updateRace()`, `deleteRace()`, `getOpenRaces()` (Stream)
  - **Participação**: `joinRace()`
  - **Telemetria**: `updatePilotLocation()`, `sendTelemetryBatch()`, `getRaceLocations()` (Stream)
  - **Sessões/Voltas**: `getLaps()`, `getSessionLaps()`, `getHistorySessions()`, `getHistorySessionLaps()`
  - **Eventos**: `getActiveEventForTrack()`, `getEventActiveSessionStream()` (Stream)
  - **Competidores**: `getCompetitors()`, `getCompetitorByUid()`, `getCompetitorsStream()` (Stream)
  - **Passagens**: `getPassingsStream()` (Stream com filtragem por janela de tempo)
  - **Limpeza**: `clearRaceParticipants()`, `clearRaceParticipantsLaps()`, `archiveCurrentLaps()`

### TelemetryService

- **Arquivo**: `lib/features/services/telemetry_service.dart`
- **Extends**: `ChangeNotifier`
- **Responsabilidade**: Coleta e sincronização de dados GPS
- **Funcionalidades**:
  - Stream GPS via `geolocator` (intervalo de 50ms)
  - Buffer em memória com sync periódico (a cada 5 segundos)
  - Gerenciamento de wakelock (tela ligada durante gravação)
  - Cálculo de frequência (Hz)
  - Geração de Session ID (formato: `dd-MM-yyyy HH:mm:ss`)
  - Detecção de checkpoints e gerenciamento de voltas
- **Métodos principais**: `startRecording()`, `stopRecording()`, `setCheckpoints()`
- **Recuperação de erros**: Buffer repovoado com dados em caso de falha de sync

### LocalDatabaseService

- **Arquivo**: `lib/features/services/local_database_service.dart`
- **Responsabilidade**: Cache SQLite offline para telemetria
- **Padrão**: Singleton
- **Database**: `speed_data_telemetry.db`
- **Tabela**: `telemetry` (id, raceId, uid, lat, lng, speed, heading, timestamp, synced)
- **Métodos**: `insertPoint()`, `getUnsyncedPoints()`, `markAsSynced()`, `clearSynced()`

### RouteService

- **Arquivo**: `lib/features/services/route_service.dart`
- **Responsabilidade**: Cálculo de rotas via Google Directions API
- **Método**: `getRouteBetweenPoints(List<LatLng>)` - retorna coordenadas detalhadas da rota

---

## Fluxo de Dados Principal

```
GPS Hardware (Geolocator, 50ms)
    |
    v
TelemetryService - Buffer em memória (List)
    |
    v
Timer periódico (5 segundos)
    |
    v
FirestoreService.sendTelemetryBatch()
    |
    v
Firebase Cloud Function (ingestTelemetry)
    |
    +---> Detecção de checkpoints e cálculo de voltas
    |
    +---> Criação de registros em races/{raceId}/participants/{uid}/laps
    |
    +---> Criação de registros em races/{raceId}/passings (apenas participant_uid)
    |
    +---> Pub/Sub para processamento assíncrono
    |
    v
Firestore Database (races/participants/sessions/laps/passings)
    |
    v
Firestore Streams (snapshots em tempo real)
    |
    v
UI StreamBuilders (atualização automática)
    |
    +---> PassingsPanel: Resolução dinâmica de nomes via getCompetitorByUid()
    |
    +---> PassingsPanel: Cálculo automático de número de voltas
```

### Processamento em Background

- **Android**: Foreground Service com notificação ("Race Recording - Telemetry is being captured")
- **Wakelock**: Impede que o dispositivo durma durante gravação
- **Offline**: SQLite como backup local; sync automático quando conectividade restaurada

---

## Atualizacoes Recentes (Implementado)

### Piloto - Available Races / Eventos
- **Card de evento ativo**: exibe evento registrado no periodo atual, nome do evento e pista. Quando ha sessao ativa, card fica verde (bandeira) e mostra CTA para abrir Live Timer.
- **CTA destacado**: botao "GO TO LIVE TIMER" com alto contraste (texto na cor da bandeira, fundo claro).
- **Texto em ingles**: mensagens do card e da lista de pistas em ingles.
- **Proxima sessao**: mostra horario previsto de inicio (HH:mm).
- **Practice tracks bloqueadas**: quando ha sessao ativa para o usuario, a lista de pistas de treino fica desabilitada e com aviso explicativo.
- **Eventos (area nova)**: tela de eventos para piloto com "My events" e "Other events" e cronograma por evento em ordem cronologica.

### Piloto - Live Timer
- **Tres modos**: Simple (Best/Previous/Current), Classic (Current + Track Chart), Gauge (Gauge + Current).
- **Status da sessao**: indicador reflete bandeira (verde/amarela/vermelha/quadriculada).
- **Borda por bandeira**: borda do Live Timer acompanha a bandeira da sessao.
- **Nome da sessao**: exibido no AppBar; nome do evento em label discreto.
- **Best/Previous/Current**: calculados na sessão ativa com base em laps (fallback passings); Best respeita tempo mínimo (Minimum Lap Time) e validade.
- **Current fluido**: cronometro atualizado em intervalos curtos para evitar saltos.
- **Simulação (modo desenvolvimento)**: sem botões Start/Stop no Live Timer; quando habilitada para o usuário, inicia automaticamente com sessão ativa e exibe apenas label + controle de velocidade.
- **Retorno para Live Timer**: ao reabrir a tela, a sessão ativa é pré-carregada para reduzir tempo de espera.
- **Sem START/FINISH**: removidos os botoes manuais de start/finish do Live Timer.
- **Warmup (bandeira)**: bandeira roxa WARMUP exibida no status e nas cores do Live Timer.

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

### Admin - Timing / Results / Passings / Track Chart
- **Results**: mostra resultado da sessao (treino/qualificacao por melhor tempo valido; corrida por numero de voltas).
- **Best/Last/Total/Laps**: calculados por passings; Total = tempo entre primeira e ultima passagem.
- **Best mostra numero da volta**: formato "tempo (volta)".
- **Min lap time**: voltas abaixo do minimo sao invalidas para resultado.
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

---

## Estrutura do Firestore

```
/users/{uid}
  ├── role: "pilot" | "admin" | "root"
  ├── name: string
  └── color: number (ARGB)

/races/{raceId}
  ├── name: string
  ├── creator_id: string (uid)
  ├── created_at: timestamp
  ├── status: "open" | "closed"
  ├── checkpoints: [{lat, lng}, ...]
  ├── route_path: [{lat, lng}, ...]
  │
  ├── /passings/{passingId}
  │   ├── participant_uid: string (uid do competidor)
  │   ├── lap_number: number (calculado pela Cloud Function)
  │   ├── lap_time: number (milissegundos)
  │   ├── timestamp: timestamp (Firestore Timestamp)
  │   ├── session_id: string
  │   ├── checkpoint_index: number (0 = linha de chegada)
  │   ├── flags: array (best_lap, personal_best, invalid, etc.)
  │   └── sector_time: number | null
  │
  └── /participants/{uid}
      ├── uid: string
      ├── display_name: string
      ├── color: string (numeric)
      ├── joined_at: timestamp
      ├── current: {lat, lng, speed, heading, timestamp, last_updated}
      │
      ├── /sessions/{sessionId}
      │   └── /laps/{lapId}
      │       └── {dados da volta}
      │
      ├── /history_sessions/{sessionId}
      │   ├── archived_at: timestamp
      │   └── /laps/{lapId}
      │       └── {dados da volta}
      │
      └── /laps/{lapId}
          └── {dados da volta}
```

---

## Navegação (GoRouter)

### Rotas definidas

| Rota | Widget | Descrição |
|------|--------|-----------|
| `/` | Home (ou Login se deslogado) | Rota inicial |
| `/login` | LoginWidget | Autenticação |
| `/signUp` | SignUpWidget | Cadastro |
| `/pilotProfileSetup` | PilotProfileSetupWidget | Setup de perfil do piloto |
| `/homePage` | HomePageWidget | Roteador principal |
| `/landingPage` | LandingPageWidget | Seleção de papel |

### Navegação interna (Navigator.push)

```
HomePageWidget
  ├── Admin/Root → AdminDashboard
  │     ├── → CreateRaceScreen (nova corrida)
  │     ├── → CreateRaceScreen (editar, com params)
  │     └── → AdminMapView (monitorar ao vivo)
  │
  └── Pilot → PilotDashboard
        ├── → GpsTestScreen → ActiveRaceScreen
        └── → PilotRaceStatsScreen (bottom sheet)
```

---

## Stack Tecnológica

| Camada | Tecnologia |
|--------|------------|
| **Frontend** | Flutter (Dart) + FlutterFlow |
| **Autenticação** | Firebase Auth (Email, Google, Apple, GitHub) |
| **Banco de Dados** | Cloud Firestore (primário) + SQLite (backup offline) |
| **Backend** | Google Cloud Functions + Pub/Sub |
| **Mapas/Localização** | Google Maps Flutter + Geolocator |
| **Roteamento** | GoRouter |
| **Estado** | Provider + ChangeNotifier + StreamBuilder |
| **Gráficos** | fl_chart |
| **Outros** | wakelock_plus, rxdart, intl, google_fonts |

---

## Modelos de Dados

### UserRole (Enum)

- **Arquivo**: `lib/features/models/user_role.dart`
- **Valores**: `pilot`, `admin`, `root`, `unknown`
- **Métodos**: `fromString()`, `toStringValue()`
- **Suporte bilíngue**: "pilot"/"piloto", "admin"/"administrador"

### PilotStats (Classe)

- **Arquivo**: `lib/features/screens/admin/widgets/leaderboard_panel.dart`
- **Campos**: `uid`, `displayName`, `averageLapTime`, `bestLapTime`, `completedLaps`, `currentLapNumber`, `currentPoints`, `intervalStrings`

### SpeedDataFirebaseUser (Auth)

- **Arquivo**: `lib/auth/firebase_auth/firebase_user_provider.dart`
- **Campos**: `user` (Firebase User), `loggedIn`, `authUserInfo`
