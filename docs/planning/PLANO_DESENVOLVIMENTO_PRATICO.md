# Plano De Desenvolvimento Pratico

## 1. Premissas Nao Negociaveis

- Nao quebrar nada que ja esta funcional hoje (fluxo piloto, admin, team, auth, timing e ingestao).
- Manter arquitetura atual como base: Flutter + Firebase (Firestore, Functions, Auth, Pub/Sub, BigQuery).
- Evoluir por camadas, com entregas pequenas e validacao em pista/evento real.
- So mover para refactor estrutural quando houver cobertura de regressao minima.

## 2. Diagnostico Tecnico Da Base Atual (10/04/2026)

- Speed Eventos: ja existe criacao/gestao de eventos, sessoes, competidores, race control e lista para piloto.
- Speed Chrono: ja existe live timer, telemetria local/offline-first, lap times por sessao, dados analiticos e passings.
- Comunicacao em tempo real: bandeiras, status de sessao e alertas de piloto ja existem (backend + telas).
- Speed Pay: ainda nao existe modulo dedicado de cobranca/conciliacao dentro do app.
- Stack do plano inicial com Supabase precisa ser adaptada para Firebase para evitar regressao e retrabalho.

## 3. Objetivo Pratico Da Proxima Janela

- Garantir operacao confiavel para os marcos:
  - 19/04/2026: inscricao e operacao basica de evento.
  - 26/04/2026: validacao de uso em pista com live e comunicacao.
  - 03/05/2026: operacao completa em evento oficial com estabilidade.
- Consolidar base para monetizacao progressiva (evento -> assinatura -> B2B federacao).

## 4. Roadmap Em 6 Fases (Alinhado Ao Backlog E A Reuniao)

## Fase 1 - MVP Operacional De Evento (ate 19/04/2026)

- Foco: entrada de usuario e operacao administrativa minima.
- Entregas:
  - fluxo de inscricao fechado ponta a ponta;
  - categoria/grupo e sessao com validacoes;
  - status financeiro simples (pendente/pago manual pix);
  - UX de inscricao sem ruido para piloto.
- Risco principal: quebrar fluxo atual de eventos.
- Mitigacao: feature flag + testes manuais em evento real de homologacao.

## Fase 2 - Validacao Em Pista (26/04/2026)

- Foco: comunicacao e resposta em tempo real.
- Entregas:
  - alertas de bandeira e box consistentes no piloto;
  - tela live simplificada com status de sessao e feedback claro;
  - confiabilidade de recebimento com fallback visual.
- Risco principal: latencia/perda de mensagem.
- Mitigacao: monitoramento de streams por sessao + log de erro e reconexao automatica.

## Fase 3 - Operacao Evento Oficial (03/05/2026)

- Foco: estabilidade operacional com usuario real.
- Entregas:
  - cronograma operacional funcional;
  - painel admin para controle de bandeira/box/mensagem;
  - resultados e participantes com consistencia por sessao;
  - checklist de "go/no-go" antes da largada.
- Risco principal: gargalo operacional no dia do evento.
- Mitigacao: ensaio completo (dry run) com roteiro e responsavel por area.

## Fase 4 - Core De Performance (pos 03/05/2026)

- Foco: retencao de piloto com valor de dados.
- Entregas:
  - comparacao melhor volta vs atual;
  - comparacao por setores e historico de treino;
  - base de compartilhamento com coach.

## Fase 5 - Diferencial Competitivo (continuo)

- Foco: vantagem em tempo real dentro do carro.
- Entregas:
  - delta em tempo real (ganhando/perdendo);
  - comparacao com lider por categoria;
  - audio automatico para feedback sem distracao visual.

## Fase 6 - Monetizacao E Escala (continuo)

- Foco: modelo economico sustentavel.
- Entregas:
  - cobranca por evento (R$ 20 a R$ 50 por piloto);
  - assinatura Pro para Speed Chrono;
  - pacote federacao (B2B) com operacao oficial.

## 5. Ordem De Execucao Recomendada

1. Blindagem de regressao dos fluxos atuais (baseline de teste rapido).
2. Fase 1 completa com foco em inscricao e operacao administrativa.
3. Fase 2 para comunicacao em tempo real em pista.
4. Fase 3 para evento oficial com estabilidade e observabilidade.
5. Fases 4, 5 e 6 em ondas incrementais sem parar operacao.

## 6. Padrao De Implementacao (para todas as features)

1. Partir sempre de `develop` atualizado.
2. Criar branch `feature/<nome-da-feature>`.
3. Implementar escopo minimo viavel da feature.
4. Rodar validacoes locais.
5. Abrir PR com checklist de nao regressao.
6. Merge somente apos validacao funcional.

## 7. Gates De Qualidade Minimos

- Build Flutter sem erro.
- Fluxo piloto: abrir dashboard, entrar live timer e receber status de sessao.
- Fluxo admin: abrir evento, controlar sessao e visualizar passings/results.
- Fluxo evento: inscricao e lista de inscritos consistente.
- Cloud Functions sem erro novo de ingestao/processamento.

## 8. Observacao Estrategica

- O plano inicial citava Supabase para Fase 1/2, mas a base produtiva atual esta em Firebase.
- Para preservar estabilidade, o plano pratico desta pasta assume evolucao no stack atual, sem migracao de backend nesta etapa.
