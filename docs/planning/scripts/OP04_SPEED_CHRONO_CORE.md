# OP04 - Speed Chrono Core

## Feature branch

`feature/op04-speed-chrono-core`

## Script de pre-voo (obrigatorio)

```powershell
$feature = "feature/op04-speed-chrono-core"
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
- O app ja possui live timer, lap times, telemetria local e analise por sessao.
- Premissa absoluta: nao quebrar o pipeline atual de timing local/offline-first.

Objetivo:
Evoluir o Speed Chrono para valor competitivo em pista com comparacoes em tempo real e leitura facil para piloto.

Escopo minimo:
1) Comparar volta atual vs melhor volta (delta em tempo real).
2) Comparar volta atual vs referencia da sessao (lider da categoria quando disponivel).
3) Exibir feedback por setor/checkpoint com ganho/perda.
4) Preparar base de audio feedback (anuncio de volta/delta), controlado por flag.

Arquivos candidatos:
- lib/features/screens/pilot/active_race_screen.dart
- lib/features/screens/pilot/lap_times_screen.dart
- lib/features/services/telemetry_service.dart
- lib/features/services/firestore_service.dart
- firebase/functions/index.js (somente se precisar enriquecer resumo por categoria)

Regras de seguranca:
- Preservar metricas atuais Best/Previous/Current.
- Nao degradar frequencia de captura/sync.
- Nao remover compatibilidade com sessao legacy/historica.

Validacao minima:
- flutter analyze
- delta atualiza em tempo real sem travar UI
- comparacao com melhor volta confere com dados persistidos
- regressao zero em live timer e lap times existentes

Entrega esperada:
- feature de comparacao/delta funcional
- toggle de ativacao para rollout seguro
- lista de arquivos alterados
```

## Criterio de aceite

- Piloto visualiza delta e comparacoes sem perda de legibilidade.
- Dados conferem com laps/crossings da sessao.
- Funcionalidades atuais do live timer permanecem estaveis.
