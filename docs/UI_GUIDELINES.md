# Speed Data - Diretrizes de UI/UX

> Guia de design para toda a interface do Speed Data.
> Direção visual: **Dark-first, data-driven, motorsport-grade.**

---

## 1. Filosofia de Design

### Princípios Fundamentais

| Princípio | Significado | Exemplo prático |
|-----------|-------------|-----------------|
| **Glanceable** | Informação absorvida em < 2 segundos | Tempo de volta em fonte 32 sp, não 14 sp |
| **Data-first** | Dados são protagonistas, chrome é mínimo | Sem bordas decorativas; espaço branco direciona o olhar |
| **Motorsport-native** | A interface fala a linguagem do automobilismo | Cores de bandeira, terminologia de timing |
| **Context-aware** | A UI se adapta ao momento de uso | Corrida ao vivo = alto contraste, pós-corrida = densidade informacional |
| **Confidence-building** | O usuário sempre sabe o que está acontecendo | Estados de loading, feedback háptico, confirmações visuais |

### Por que Dark-First?

1. **Uso outdoor**: pilotos e admins operam em boxes, pistas — dark theme com alto contraste reduz glare sob luz solar direta
2. **Padrão da indústria**: F1 TV, MoTeC i2, AiM Race Studio, Orbits — todo software de timing/telemetria é dark
3. **Hierarquia de dados**: dados luminosos sobre fundo escuro criam hierarquia natural — o olho vai direto ao que importa
4. **Fadiga visual**: sessões longas de monitoramento (admins) se beneficiam de dark theme
5. **Percepção de marca**: dark theme transmite performance, precisão, tecnologia de ponta

---

## 2. Paleta de Cores

### Core Palette

```
Background Hierarchy (Dark):
┌─────────────────────────────────────────────┐
│  bg-base       #0D0D0F   Fundo principal    │
│  bg-surface    #161619   Cards, painéis      │
│  bg-elevated   #1E1E22   Elementos elevados  │
│  bg-overlay    #26262B   Modais, drawers     │
└─────────────────────────────────────────────┘

Text Hierarchy:
┌─────────────────────────────────────────────┐
│  text-primary    #F0F0F2   Dados principais  │
│  text-secondary  #9898A0   Labels, meta      │
│  text-disabled   #4A4A52   Estados inativos  │
└─────────────────────────────────────────────┘

Borders & Dividers:
┌─────────────────────────────────────────────┐
│  border-subtle   #2A2A30   Divisores leves   │
│  border-default  #3A3A42   Bordas de card     │
│  border-focus    #5B8DEF   Estado de foco     │
└─────────────────────────────────────────────┘
```

### Accent Colors (Funcionais)

| Token | Hex | Uso |
|-------|-----|-----|
| `accent-primary` | `#5B8DEF` | CTAs, links, seleções, foco |
| `accent-primary-muted` | `#5B8DEF` @ 15% | Backgrounds de seleção, hover states |
| `accent-secondary` | `#8B5CF6` | Elementos secundários, badges de sessão |

### Semantic Colors (Motorsport)

| Token | Hex | Uso |
|-------|-----|-----|
| `flag-green` | `#22C55E` | Bandeira verde, pista livre, sucesso, GPS ativo |
| `flag-yellow` | `#EAB308` | Bandeira amarela, cautela, avisos |
| `flag-red` | `#EF4444` | Bandeira vermelha, parada, erros, desconectado |
| `flag-checkered` | `#F0F0F2` | Sessão finalizada (padrão xadrez se possível) |
| `flag-blue` | `#3B82F6` | Bandeira azul, informações |

### Data Colors (Gráficos e Telemetria)

| Token | Hex | Uso |
|-------|-----|-----|
| `data-speed` | `#06B6D4` | Velocidade (cyan — padrão telemetria) |
| `data-best` | `#A855F7` | Melhor volta (roxo — padrão F1) |
| `data-current` | `#F0F0F2` | Volta atual |
| `data-comparison` | `#6B7280` | Voltas de comparação |
| `data-positive` | `#22C55E` | Delta positivo (mais rápido) |
| `data-negative` | `#EF4444` | Delta negativo (mais lento) |

### Pilot Colors

Manter o sistema de 21 cores para identificação de pilotos no mapa e leaderboard. Essas cores devem ter:
- Saturação alta (80-100%) para visibilidade sobre fundo escuro
- Luminosidade entre 50-70% para não "estourar" em dark theme
- Contraste mínimo de 4.5:1 contra `bg-surface`

---

## 3. Tipografia

### Font Stack

```
Primária (UI):       Inter (Google Fonts)
Dados / Monospace:   JetBrains Mono (Google Fonts)
```

**Por que Inter?** Projetada para telas, excelente legibilidade em tamanhos pequenos, suporte amplo a pesos, números tabulares. Estética clean-tech sem ser genérica.

**Por que JetBrains Mono?** Tempos de volta, coordenadas, telemetria — tudo que é número precisa de fonte monospace com alinhamento tabular para scanability. Ligaduras tipográficas como ≥ e → são um bônus funcional.

### Escala Tipográfica

| Token | Tamanho | Peso | Uso |
|-------|---------|------|-----|
| `display-lg` | 40 sp | Bold (700) | Tempo de volta principal, velocidade hero |
| `display-md` | 32 sp | Bold (700) | Posição, melhor volta |
| `display-sm` | 24 sp | SemiBold (600) | Contadores, estatísticas destaque |
| `heading-lg` | 20 sp | SemiBold (600) | Títulos de seção, nome de tela |
| `heading-md` | 18 sp | SemiBold (600) | Subtítulos, nome de painel |
| `heading-sm` | 16 sp | Medium (500) | Títulos de card |
| `body-lg` | 16 sp | Regular (400) | Texto principal, descrições |
| `body-md` | 14 sp | Regular (400) | Texto padrão, labels de formulário |
| `body-sm` | 12 sp | Regular (400) | Metadata, captions |
| `mono-lg` | 24 sp | Medium (500) | Tempos de volta (JetBrains Mono) |
| `mono-md` | 16 sp | Regular (400) | Coordenadas, dados numéricos |
| `mono-sm` | 12 sp | Regular (400) | Timestamps, IDs |

### Regras Tipográficas

1. **Tempos de volta SEMPRE em monospace** — `01:23.456` precisa de alinhamento tabular para comparação visual instantânea
2. **Números tabulares** (`fontFeatures: [FontFeature.tabularFigures()]`) em todas as tabelas e leaderboards
3. **Sem itálico** em dados — itálico reduz legibilidade em telas pequenas e sob vibração (piloto em pista)
4. **Letter-spacing** de +0.5 em labels small caps para legibilidade

---

## 4. Spacing & Layout

### Grid System

```
Base unit:    4 dp
Spacing scale: 4, 8, 12, 16, 20, 24, 32, 40, 48, 64

Padding padrão de tela:   16 dp (mobile) / 24 dp (tablet+)
Gap entre cards:           12 dp
Padding interno de card:   16 dp
Padding interno de painel: 12 dp (compacto) / 16 dp (padrão)
```

### Breakpoints (Responsividade)

| Breakpoint | Largura | Layout |
|------------|---------|--------|
| `compact` | < 600 dp | Mobile — Single column, bottom navigation |
| `medium` | 600 – 840 dp | Tablet portrait — Two column onde relevante |
| `expanded` | > 840 dp | Tablet landscape / Desktop — Master-detail, multi-panel |

### Layout por Contexto

**Corrida ao vivo (Piloto)**:
- Mapa ocupa ~70% da tela
- Painel de telemetria fixo no bottom (overlay translúcido)
- Informações mínimas: velocidade, volta atual, tempo
- Zero scroll — tudo visível sem interação

**Corrida ao vivo (Admin)**:
- Layout de 2 ou 3 painéis em telas > 840 dp
- Mapa + Leaderboard como layout principal
- Passings e controles como painéis colapsáveis
- Em mobile: tab navigation entre Map / Leaderboard / Controls

**Pós-corrida (Piloto)**:
- Full-width para gráficos de telemetria
- Lista de voltas colapsável na lateral (desktop) ou bottom sheet (mobile)
- Densidade informacional alta é OK — o contexto é análise

**Gerenciamento (Admin)**:
- Formulários usam max-width de 640 dp para legibilidade
- Master-detail para listas (eventos, grupos, sessões)
- Formulários em abas para organizar campos sem scroll excessivo

---

## 5. Componentes

### 5.1 Cards

```
┌──────────────────────────────────────┐
│  bg-surface                          │
│  border-radius: 12 dp               │
│  border: 1px border-subtle           │
│  padding: 16 dp                      │
│  elevation: 0 (sem box-shadow)       │
│                                      │
│  Hover/Press: bg → bg-elevated       │
│  Selected: border → accent-primary   │
│             bg → accent-primary-muted│
└──────────────────────────────────────┘
```

- **Sem sombras** — a hierarquia vem de variação de background, não de elevation
- **Bordas sutis** — 1px `border-subtle` define limites sem peso visual
- Cards interativos têm estado hover com transição de 150ms

### 5.2 Botões

**Primary (CTA)**:
```
bg: accent-primary
text: #FFFFFF
border-radius: 8 dp
height: 48 dp (touch target)
padding-h: 24 dp
font: body-md, SemiBold
```

**Secondary (Outline)**:
```
bg: transparent
text: text-primary
border: 1.5px accent-primary
border-radius: 8 dp
height: 48 dp
```

**Ghost (Texto)**:
```
bg: transparent
text: accent-primary
border: none
height: 40 dp
```

**Danger (Destrutivo)**:
```
bg: flag-red
text: #FFFFFF
border-radius: 8 dp
// Usado apenas para ações irreversíveis com confirmação
```

**Flag Buttons (Race Control)**:
```
Botões grandes (64x64 dp mínimo) com a cor da bandeira
Ícone central + label abaixo
border-radius: 12 dp
Feedback háptico ao pressionar
Estado ativo: glow sutil na cor da bandeira
```

### 5.3 Inputs & Forms

```
bg: bg-surface
border: 1.5px border-default
border-radius: 8 dp
height: 48 dp
padding-h: 16 dp
font: body-md

Focus:  border → border-focus
        glow sutil (box-shadow: 0 0 0 3px accent-primary @ 20%)
Error:  border → flag-red
        helper text em flag-red abaixo do campo
```

- Labels sempre acima do campo (não placeholder-as-label)
- Placeholder text em `text-disabled`
- Helper text em `text-secondary`, 12 sp

### 5.4 Tabs

```
Estilo: Underline tabs (não pill tabs)
─────────────────────────────────────
  Setup    Registration    Timing
  ─────

Tab ativa:   text-primary + underline 2px accent-primary
Tab inativa: text-secondary
Transição:   150ms ease-out
```

### 5.5 Data Table (Leaderboard)

```
┌─────┬────────────┬──────────┬──────────┬────────┐
│ Pos │ Driver     │ Best Lap │ Last Lap │ Gap    │
├─────┼────────────┼──────────┼──────────┼────────┤
│  1  │ ● PILOTO A │ 1:23.456 │ 1:24.012 │  ---   │  ← row bg: bg-surface
│  2  │ ● PILOTO B │ 1:23.890 │ 1:25.111 │ +0.434 │  ← row bg: bg-base (alternado)
│  3  │ ● PILOTO C │ 1:24.102 │ 1:24.500 │ +0.646 │
└─────┴────────────┴──────────┴──────────┴────────┘

● = Dot com a cor do piloto (12 dp, preenchido)
Tempos: mono-md, alinhamento à direita
Gap positivo: text-secondary
Melhor volta global: highlight com data-best na row inteira
Melhor volta pessoal: highlight apenas na célula do tempo
Header: text-secondary, body-sm, UPPERCASE, letter-spacing +1
Row height: 44 dp
Dividers: border-subtle (horizontal only)
```

### 5.6 Map Overlays

```
Painel de telemetria (overlay no mapa):
┌──────────────────────────────────┐
│  bg: bg-base @ 85% opacity      │
│  backdrop-filter: blur(16px)     │
│  border-radius: 16 dp (top)     │
│  padding: 16 dp                 │
│                                  │
│   142          Lap 3/10          │
│   km/h         1:23.456         │
│                                  │
│   Velocidade: display-lg         │
│   Unidade: body-sm, secondary    │
│   Tempo: mono-lg                 │
└──────────────────────────────────┘
```

- Overlays usam glassmorphism leve (blur + opacidade) para manter visibilidade do mapa
- Informações mínimas — velocidade e tempo são prioridade 1
- Elementos reposicionáveis futuramente (considerar no design)

### 5.7 Status Indicators

**GPS Status**:
```
● Verde pulsante  = GPS ativo, sinal bom
● Amarelo         = GPS ativo, sinal fraco
● Vermelho        = Sem sinal GPS
○ Cinza           = GPS desativado
```

**Connection Status**:
```
Barra de status (top):
  Online:   ícone wifi em flag-green, oculto após 2s
  Syncing:  ícone sync rotacionando em flag-yellow
  Offline:  banner persistente em flag-red @ 10%, texto flag-red
```

**Race Status**:
```
Badge pill:
  Open:     bg flag-green @ 15%, text flag-green
  Live:     bg flag-green @ 15%, text flag-green, dot pulsante
  Finished: bg text-disabled @ 15%, text text-secondary
  Red Flag: bg flag-red @ 15%, text flag-red
```

### 5.8 Bottom Sheets

```
bg: bg-surface
border-radius: 16 dp (top-left, top-right)
handle: 32 x 4 dp, border-default, center-top, margin-top 8dp

Snap points:
  - Collapsed: 15% da tela (peek)
  - Half: 50% da tela
  - Expanded: 90% da tela (nunca 100% — manter contexto visual)
```

### 5.9 Chips & Badges

```
Chip (seleção, filtro):
  bg: bg-elevated
  border: 1px border-default
  border-radius: 20 dp (pill)
  height: 32 dp
  padding-h: 12 dp
  font: body-sm, Medium

  Selected:
    bg: accent-primary @ 15%
    border: accent-primary
    text: accent-primary

Badge (contagem, status):
  bg: accent-primary (ou semantic color)
  text: #FFFFFF
  border-radius: 10 dp
  min-width: 20 dp
  height: 20 dp
  font: 11 sp, SemiBold
```

---

## 6. Iconografia

### Estilo

- **Linha fina** (stroke weight 1.5px) — consistente com estética clean
- **Filled** apenas para estados ativos ou ícones de navegação selecionados
- **Tamanho padrão**: 24 dp (touch areas de 48 dp)
- **Cor padrão**: `text-secondary`, ativo: `text-primary` ou `accent-primary`
- **Biblioteca sugerida**: `lucide_icons` (leve, consistente, open-source) ou Material Symbols (Outlined, weight 300)

### Ícones Específicos do Domínio

| Contexto | Ícone sugerido |
|----------|---------------|
| GPS/Localização | MapPin |
| Velocidade | Gauge |
| Volta/Lap | RotateCcw |
| Timer/Tempo | Timer |
| Bandeira | Flag |
| Piloto | User / Helmet custom |
| Corrida ao vivo | Radio (dot pulsante) |
| Configuração | Settings |
| Telemetria | Activity |
| Checkpoint | CircleDot |

---

## 7. Motion & Animação

### Princípios

1. **Funcional, não decorativa** — animação serve para orientar, não entreter
2. **Rápida** — o contexto é corrida; 150-300ms no máximo para transições de UI
3. **Dados em tempo real não animam entrada** — leaderboard, posições no mapa, telemetria atualizam instantaneamente (sem fade-in que atrase informação)

### Curvas e Durações

| Tipo | Duração | Curva | Exemplo |
|------|---------|-------|---------|
| Micro-interaction | 100-150ms | `easeOut` | Hover, press, toggle |
| Transição de estado | 200ms | `easeInOut` | Tab switch, card expand |
| Navegação de tela | 300ms | `easeInOut` | Push/pop de tela |
| Bottom sheet | 250ms | `easeOut` | Snap to position |
| Dados em tempo real | 0ms | — | Leaderboard, mapa, telemetria |

### Animações Específicas

- **Dot pulsante (GPS/Live)**: scale 1.0 → 1.4, opacity 1.0 → 0.0, duration 1.5s, loop infinito
- **Posição no mapa**: interpolação linear da posição anterior para nova (smooth tracking)
- **Troca de posição no leaderboard**: animação de reordenação 200ms (AnimatedList)
- **Gráficos de velocidade**: desenho progressivo da linha na primeira renderização, depois updates instantâneos

---

## 8. Padrões por Contexto de Uso

### 8.1 Em Pista (Piloto — Tela de Corrida)

**Premissas**: sol direto, vibração, atenção dividida, luvas podem dificultar toque

- **Contraste**: mínimo WCAG AAA (7:1) para dados críticos
- **Touch targets**: mínimo 56 dp (maior que o padrão de 48 dp)
- **Informação**: apenas o essencial — velocidade, volta, tempo
- **Orientação**: landscape preferencial (dispositivo montado no veículo)
- **Brilho**: considerar forçar brilho máximo durante corrida ativa (já há wakelock)
- **Cores**: evitar vermelho/verde como único diferenciador (daltonismo) — usar ícone + cor

### 8.2 Nos Boxes (Piloto — Análise Pós-Corrida)

**Premissas**: ambiente controlado, atenção focada, análise detalhada

- **Densidade**: alta — gráficos, tabelas, dados comparativos
- **Interação**: scroll, pinch-to-zoom em gráficos, seleção de voltas
- **Orientação**: portrait e landscape suportados
- **Typography**: pode usar tamanhos menores (body-sm) para dados secundários

### 8.3 Controle de Corrida (Admin — Race Control)

**Premissas**: multiplex de informações, decisões rápidas, pressão temporal

- **Layout**: multi-painel (mapa + leaderboard + passings + controles)
- **Hierarchy**: bandeiras e alertas no topo da hierarquia visual
- **Botões de bandeira**: grandes, com cores óbvias, confirmação antes de ação
- **Leaderboard**: auto-scroll para relevante, mas permitir scroll manual (não roubar controle)
- **Audio feedback**: considerar sons para eventos críticos (passagem, bandeira)

### 8.4 Escritório (Admin — Gestão de Eventos)

**Premissas**: desktop/tablet, sem pressão temporal, setup antecipado

- **Formulários**: padrão com validação inline, agrupados em abas
- **Navegação**: master-detail, breadcrumbs para hierarquia (Evento > Grupo > Sessão)
- **Feedback**: toast notifications para ações de CRUD, não modais bloqueantes
- **Ações destrutivas**: confirmação com digitação (ex: "deletar evento" exige digitar nome)

---

## 9. Padrões de Feedback

### Loading States

```
Skeleton Loading (preferencial):
  - Retângulos arredondados (8 dp radius) em bg-elevated
  - Shimmer animation: gradiente linear translúcido movendo da esquerda para a direita
  - Duração do shimmer: 1.5s, loop
  - Formas que espelham o layout final (não spinners genéricos)

Spinner (apenas quando skeleton não faz sentido):
  - CircularProgressIndicator
  - Cor: accent-primary
  - Tamanho: 24 dp (inline) ou 40 dp (page-level)
  - Acompanhado de texto descritivo: "Carregando corridas..." (não apenas spinner)
```

### Empty States

```
Layout centralizado vertical:
  - Ícone: 64 dp, text-disabled
  - Título: heading-md, text-primary
  - Descrição: body-md, text-secondary, max-width 280 dp
  - CTA (opcional): botão primary

Exemplo:
  [ícone de bandeira]
  "Nenhuma corrida ativa"
  "Aguarde o admin iniciar uma sessão ou verifique a conexão."
```

### Toast / Snackbar

```
bg: bg-elevated
border-left: 4px (semantic color: green/yellow/red/blue)
border-radius: 8 dp
padding: 12 dp 16 dp
position: bottom-center, 16 dp acima do bottom nav
max-width: 400 dp
duration: 4s (info), 6s (warning), persistent (error com ação)

Texto: body-md, text-primary
Ação: ghost button, accent-primary
```

### Confirmação de Ações Destrutivas

```
Modal centralizado:
  bg: bg-surface
  border-radius: 16 dp
  max-width: 400 dp

  Ícone: 48 dp, flag-red, no topo
  Título: heading-lg, "Encerrar corrida?"
  Descrição: body-md, text-secondary

  Botões: [Cancelar (ghost)]  [Confirmar (danger)]
  Botão de confirmar desabilitado por 2s para ações críticas
```

---

## 10. Acessibilidade

### Requisitos Mínimos

| Critério | Padrão |
|----------|--------|
| Contraste de texto | WCAG AA (4.5:1) mínimo; AAA (7:1) para dados em pista |
| Touch targets | 48 dp mínimo (56 dp em contexto de corrida) |
| Focus indicators | Visíveis (ring de 2px accent-primary, offset 2px) |
| Screen readers | Labels descritivos em todos os botões e ícones |
| Daltonismo | Nunca usar cor como único diferenciador — sempre cor + forma/ícone/texto |

### Color Blind Safe Patterns

- Posições no leaderboard: número + cor do piloto + nome (3 identificadores)
- Deltas de tempo: verde/vermelho + seta ↑↓ + sinal +/-
- Status badges: cor + texto descritivo
- Bandeiras: cor + ícone + label

---

## 11. Tokens de Design — Resumo

```dart
// Sugestão de implementação em Dart/Flutter

class SpeedDataTheme {
  // Backgrounds
  static const bgBase      = Color(0xFF0D0D0F);
  static const bgSurface   = Color(0xFF161619);
  static const bgElevated  = Color(0xFF1E1E22);
  static const bgOverlay   = Color(0xFF26262B);

  // Text
  static const textPrimary   = Color(0xFFF0F0F2);
  static const textSecondary = Color(0xFF9898A0);
  static const textDisabled  = Color(0xFF4A4A52);

  // Borders
  static const borderSubtle  = Color(0xFF2A2A30);
  static const borderDefault = Color(0xFF3A3A42);
  static const borderFocus   = Color(0xFF5B8DEF);

  // Accent
  static const accentPrimary   = Color(0xFF5B8DEF);
  static const accentSecondary = Color(0xFF8B5CF6);

  // Semantic — Motorsport Flags
  static const flagGreen  = Color(0xFF22C55E);
  static const flagYellow = Color(0xFFEAB308);
  static const flagRed    = Color(0xFFEF4444);
  static const flagBlue   = Color(0xFF3B82F6);

  // Data Visualization
  static const dataSpeed      = Color(0xFF06B6D4);
  static const dataBest       = Color(0xFFA855F7);
  static const dataCurrent    = Color(0xFFF0F0F2);
  static const dataComparison = Color(0xFF6B7280);
  static const dataPositive   = Color(0xFF22C55E);
  static const dataNegative   = Color(0xFFEF4444);

  // Radii
  static const radiusSm  = 8.0;
  static const radiusMd  = 12.0;
  static const radiusLg  = 16.0;
  static const radiusFull = 999.0;

  // Spacing
  static const space4  = 4.0;
  static const space8  = 8.0;
  static const space12 = 12.0;
  static const space16 = 16.0;
  static const space20 = 20.0;
  static const space24 = 24.0;
  static const space32 = 32.0;
  static const space40 = 40.0;
  static const space48 = 48.0;
  static const space64 = 64.0;
}
```

---

## 12. Referências Visuais

Apps e sistemas que servem de benchmark para o Speed Data:

| Referência | O que pegar |
|-----------|-------------|
| **F1 App** (oficial) | Leaderboard, cores de bandeira, tipografia de dados |
| **AiM Race Studio** | Layout de telemetria, gráficos de velocidade/tempo |
| **Orbits (Racelogic)** | Dashboard de timing, UX de cronometragem |
| **Strava** | Análise pós-atividade, UX de dados esportivos em mobile |
| **Linear App** | Clean dark UI, densidade informacional bem resolvida |
| **Vercel Dashboard** | Hierarquia tipográfica, uso de monospace para dados |

---

*Última atualização: 2026-02-14*
