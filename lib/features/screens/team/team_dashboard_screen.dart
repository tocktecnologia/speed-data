import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:speed_data/features/models/competitor_model.dart';
import 'package:speed_data/features/models/event_model.dart';
import 'package:speed_data/features/models/lap_analysis_model.dart';
import 'package:speed_data/features/models/race_session_model.dart';
import 'package:speed_data/features/models/team_model.dart';
import 'package:speed_data/features/services/firestore_service.dart';
import 'package:speed_data/flutter_flow/nav/nav.dart';

class TeamDashboardScreen extends StatefulWidget {
  const TeamDashboardScreen({super.key});

  @override
  State<TeamDashboardScreen> createState() => _TeamDashboardScreenState();
}

class _TeamDashboardScreenState extends State<TeamDashboardScreen> {
  final FirestoreService _firestore = FirestoreService();
  String? _selectedEventId;
  final Set<String> _alertsInFlightByPilot = <String>{};

  String _sessionLabel(RaceSession session) {
    if (session.name.trim().isNotEmpty) return session.name.trim();
    return session.type.name.toUpperCase();
  }

  bool _isPilotAlertActionInFlight(String pilotUid) {
    final normalizedUid = pilotUid.trim();
    if (normalizedUid.isEmpty) return false;
    return _alertsInFlightByPilot.contains(normalizedUid);
  }

  void _setPilotAlertActionInFlight(String pilotUid, bool inFlight) {
    final normalizedUid = pilotUid.trim();
    if (normalizedUid.isEmpty || !mounted) return;
    setState(() {
      if (inFlight) {
        _alertsInFlightByPilot.add(normalizedUid);
      } else {
        _alertsInFlightByPilot.remove(normalizedUid);
      }
    });
  }

  bool _isAlertActive(Map<String, dynamic>? alert) {
    if (alert == null) return false;
    if (alert['active'] != true) return false;
    final message = (alert['message'] as String?)?.trim() ?? '';
    if (message.isEmpty) return false;
    final expiresAtMs = alert['expires_at_ms'];
    if (expiresAtMs is num &&
        DateTime.now().millisecondsSinceEpoch > expiresAtMs.toInt()) {
      return false;
    }
    return true;
  }

  Future<void> _sendBoxAlert({
    required String eventId,
    required String sessionId,
    required Competitor competitor,
  }) async {
    final pilotUid = competitor.uid.trim();
    if (pilotUid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Este piloto não possui conta vinculada para receber alerta.'),
        ),
      );
      return;
    }
    if (_isPilotAlertActionInFlight(pilotUid)) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar alerta BOX'),
        content: Text('Enviar "BOX" para ${competitor.name}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Enviar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    _setPilotAlertActionInFlight(pilotUid, true);
    try {
      await _firestore.sendPilotAlert(
        eventId: eventId,
        sessionId: sessionId,
        pilotUid: pilotUid,
        message: 'BOX',
        type: 'box',
        teamId: competitor.teamId,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Alerta BOX enviado para ${competitor.name}.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao enviar alerta: $e')),
      );
    } finally {
      _setPilotAlertActionInFlight(pilotUid, false);
    }
  }

  Future<void> _sendCustomAlert({
    required String eventId,
    required String sessionId,
    required Competitor competitor,
  }) async {
    final pilotUid = competitor.uid.trim();
    if (pilotUid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Este piloto não possui conta vinculada para receber alerta.'),
        ),
      );
      return;
    }
    if (_isPilotAlertActionInFlight(pilotUid)) return;

    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mensagem curta'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 32,
          decoration: const InputDecoration(
            labelText: 'Mensagem (max 32)',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Enviar'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (text == null || text.trim().isEmpty) return;

    _setPilotAlertActionInFlight(pilotUid, true);
    try {
      await _firestore.sendPilotAlert(
        eventId: eventId,
        sessionId: sessionId,
        pilotUid: pilotUid,
        message: text,
        type: 'custom',
        teamId: competitor.teamId,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Alerta enviado para ${competitor.name}.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao enviar alerta: $e')),
      );
    } finally {
      _setPilotAlertActionInFlight(pilotUid, false);
    }
  }

  Future<void> _clearAlert({
    required String eventId,
    required String sessionId,
    required Competitor competitor,
  }) async {
    final pilotUid = competitor.uid.trim();
    if (pilotUid.isEmpty || _isPilotAlertActionInFlight(pilotUid)) return;
    _setPilotAlertActionInFlight(pilotUid, true);
    try {
      await _firestore.clearPilotAlert(
        eventId: eventId,
        sessionId: sessionId,
        pilotUid: pilotUid,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Alerta removido para ${competitor.name}.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao remover alerta: $e')),
      );
    } finally {
      _setPilotAlertActionInFlight(pilotUid, false);
    }
  }

  Widget _buildPilotAlertTile({
    required RaceEvent event,
    required RaceSession? session,
    required Competitor competitor,
    required Map<String, dynamic>? alert,
  }) {
    final pilotUid = competitor.uid.trim();
    final isBusy = _isPilotAlertActionInFlight(pilotUid);
    final canSendAlert = session != null && pilotUid.isNotEmpty;
    final isActive = _isAlertActive(alert);
    final alertType = (alert?['type'] as String?)?.trim().toLowerCase() ?? '';
    final alertMessage = (alert?['message'] as String?)?.trim() ?? '';
    final isBoxActive = isActive && alertType == 'box';
    final isMsgActive = isActive && !isBoxActive;
    final statusLabel = isActive
        ? (isBoxActive ? 'Status: BOX ativo' : 'Status: MSG "$alertMessage"')
        : 'Status: sem alerta';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          child: Text(
            competitor.number.isEmpty ? '?' : competitor.number,
          ),
        ),
        title: Text(
          competitor.name.isEmpty ? competitor.id : competitor.name,
        ),
        subtitle: Text(
          '${competitor.teamName.isEmpty ? 'Equipe sem nome' : competitor.teamName}\n$statusLabel',
        ),
        isThreeLine: true,
        trailing: Wrap(
          spacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            OutlinedButton(
              style: isBoxActive
                  ? OutlinedButton.styleFrom(
                      backgroundColor: Colors.red.shade500,
                    )
                  : null,
              onPressed: !canSendAlert || isBusy
                  ? null
                  : () => _sendBoxAlert(
                        eventId: event.id,
                        sessionId: session.id,
                        competitor: competitor,
                      ),
              child: Text(isBoxActive ? 'BOX ATIVO' : 'BOX'),
            ),
            OutlinedButton(
              style: isMsgActive
                  ? OutlinedButton.styleFrom(
                      backgroundColor: Colors.lightBlue.shade100,
                    )
                  : null,
              onPressed: !canSendAlert || isBusy
                  ? null
                  : () => _sendCustomAlert(
                        eventId: event.id,
                        sessionId: session.id,
                        competitor: competitor,
                      ),
              child: Text(isMsgActive ? 'MSG ATIVA' : 'MSG'),
            ),
            IconButton(
              tooltip: 'Remover alerta',
              onPressed: !canSendAlert || isBusy || !isActive
                  ? null
                  : () => _clearAlert(
                        eventId: event.id,
                        sessionId: session.id,
                        competitor: competitor,
                      ),
              icon: isBusy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.notifications_off_outlined),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSessionResults(
    RaceEvent event,
    RaceSession session,
    List<Competitor> teamCompetitors,
  ) {
    final teamUids = teamCompetitors
        .map((competitor) => competitor.uid.trim())
        .where((uid) => uid.isNotEmpty)
        .toSet();

    return StreamBuilder<Map<String, List<LapAnalysisModel>>>(
      stream: _firestore.getSessionParticipantsLapsModels(
        event.trackId,
        sessionId: session.id,
        eventId: event.id,
      ),
      builder: (context, snapshot) {
        final lapsByUid =
            snapshot.data ?? const <String, List<LapAnalysisModel>>{};
        final entries = <Map<String, dynamic>>[];

        for (final competitor in teamCompetitors) {
          final uid = competitor.uid.trim();
          if (uid.isEmpty || !teamUids.contains(uid)) continue;
          final laps = lapsByUid[uid] ?? const <LapAnalysisModel>[];
          final validLaps = laps
              .where((lap) => lap.valid && lap.totalLapTimeMs > 0)
              .toList(growable: false);
          int? bestLapMs;
          if (validLaps.isNotEmpty) {
            bestLapMs = validLaps
                .map((lap) => lap.totalLapTimeMs)
                .reduce((a, b) => a < b ? a : b);
          }
          entries.add({
            'name': competitor.name,
            'number': competitor.number,
            'bestLapMs': bestLapMs,
            'laps': laps.length,
          });
        }

        entries.sort((a, b) {
          final aBest = a['bestLapMs'] as int?;
          final bBest = b['bestLapMs'] as int?;
          if (aBest == null && bBest == null) return 0;
          if (aBest == null) return 1;
          if (bBest == null) return -1;
          return aBest.compareTo(bBest);
        });

        if (entries.isEmpty) {
          return const Text(
            'Sem voltas disponíveis para sua equipe na sessão atual.',
            style: TextStyle(color: Colors.grey),
          );
        }

        String formatMs(int? ms) {
          if (ms == null || ms <= 0) return '--:--.---';
          final minutes = (ms ~/ 60000).toString().padLeft(2, '0');
          final seconds = ((ms % 60000) ~/ 1000).toString().padLeft(2, '0');
          final milli = (ms % 1000).toString().padLeft(3, '0');
          return '$minutes:$seconds.$milli';
        }

        return Column(
          children: entries
              .map(
                (entry) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text('${entry['number']} - ${entry['name']}'),
                  subtitle: Text('Voltas: ${entry['laps']}'),
                  trailing: Text(
                    formatMs(entry['bestLapMs'] as int?),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              )
              .toList(growable: false),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('Usuário não autenticado.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Painel da Equipe'),
      ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            UserAccountsDrawerHeader(
              decoration: const BoxDecoration(color: Colors.black),
              accountName: Text(user.displayName?.trim().isNotEmpty == true
                  ? user.displayName!
                  : 'Team Member'),
              accountEmail: Text(user.email ?? ''),
              currentAccountPicture: const CircleAvatar(
                backgroundColor: Colors.white,
                child: Icon(Icons.groups, color: Colors.black),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Sign Out'),
              onTap: () async {
                await FirebaseAuth.instance.signOut();
                if (context.mounted) {
                  context.goNamedAuth(
                    'Login',
                    context.mounted,
                    ignoreRedirect: true,
                  );
                }
              },
            ),
          ],
        ),
      ),
      body: StreamBuilder<List<TeamMembership>>(
        stream: _firestore.getTeamMembershipsStream(
          user.uid,
          email: user.email,
        ),
        builder: (context, membershipSnapshot) {
          if (membershipSnapshot.hasError) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Erro ao carregar vínculos de equipe. Tente novamente.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          if (!membershipSnapshot.hasData &&
              membershipSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final memberships =
              (membershipSnapshot.data ?? const <TeamMembership>[])
                  .where((membership) => membership.role != 'pilot')
                  .toList(growable: false);
          if (memberships.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Você não está vinculado a nenhuma equipe ativa.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final teamIdsByEvent = <String, Set<String>>{};
          for (final membership in memberships) {
            teamIdsByEvent
                .putIfAbsent(membership.eventId, () => <String>{})
                .add(membership.teamId);
          }

          return StreamBuilder<List<RaceEvent>>(
            stream: _firestore.getEventsStream(),
            builder: (context, eventsSnapshot) {
              if (!eventsSnapshot.hasData &&
                  eventsSnapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final events = (eventsSnapshot.data ?? const <RaceEvent>[])
                  .where((event) => teamIdsByEvent.containsKey(event.id))
                  .toList(growable: false)
                ..sort((a, b) => b.date.compareTo(a.date));

              if (events.isEmpty) {
                return const Center(
                  child: Text('Nenhum evento da sua equipe foi encontrado.'),
                );
              }

              if (_selectedEventId == null ||
                  !events.any((event) => event.id == _selectedEventId)) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  setState(() => _selectedEventId = events.first.id);
                });
              }

              final selectedEvent = events.cast<RaceEvent?>().firstWhere(
                    (event) => event?.id == _selectedEventId,
                    orElse: () => null,
                  );
              if (selectedEvent == null) {
                return const Center(child: CircularProgressIndicator());
              }

              final selectedTeamIds =
                  teamIdsByEvent[selectedEvent.id] ?? const <String>{};

              return StreamBuilder<List<Competitor>>(
                stream: _firestore.getCompetitorsStream(selectedEvent.id),
                builder: (context, competitorsSnapshot) {
                  final competitors =
                      competitorsSnapshot.data ?? const <Competitor>[];
                  final teamCompetitors = competitors
                      .where((competitor) =>
                          selectedTeamIds.contains(competitor.teamId.trim()))
                      .toList(growable: false)
                    ..sort((a, b) => a.name.compareTo(b.name));

                  RaceSession? activeSession;
                  try {
                    activeSession = selectedEvent.sessions.firstWhere(
                        (session) => session.status == SessionStatus.active);
                  } catch (_) {
                    activeSession = null;
                  }
                  final activeSessionId = activeSession?.id;

                  return ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              DropdownButtonFormField<String>(
                                value: selectedEvent.id,
                                decoration: const InputDecoration(
                                  labelText: 'Evento',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                                items: events
                                    .map(
                                      (event) => DropdownMenuItem<String>(
                                        value: event.id,
                                        child: Text(event.name),
                                      ),
                                    )
                                    .toList(growable: false),
                                onChanged: (value) =>
                                    setState(() => _selectedEventId = value),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                activeSession == null
                                    ? 'Sessão ativa: nenhuma'
                                    : 'Sessão ativa: ${_sessionLabel(activeSession)}',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: activeSession == null
                                      ? Colors.orange
                                      : Colors.green,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Pilotos da equipe neste evento: ${teamCompetitors.length}',
                              ),
                            ],
                          ),
                        ),
                      ),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Resumo de resultados da sessão ativa',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 8),
                              if (activeSession == null)
                                const Text(
                                  'Sem sessão ativa para exibir resultados.',
                                  style: TextStyle(color: Colors.grey),
                                )
                              else
                                _buildSessionResults(
                                  selectedEvent,
                                  activeSession,
                                  teamCompetitors,
                                ),
                            ],
                          ),
                        ),
                      ),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Alertas para pilotos da equipe',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 8),
                              if (teamCompetitors.isEmpty)
                                const Text(
                                  'Nenhum piloto vinculado à sua equipe neste evento.',
                                  style: TextStyle(color: Colors.grey),
                                )
                              else
                                ...teamCompetitors.map(
                                  (competitor) {
                                    final pilotUid = competitor.uid.trim();
                                    final canListen = activeSessionId != null &&
                                        pilotUid.isNotEmpty;
                                    return StreamBuilder<Map<String, dynamic>?>(
                                      stream: canListen
                                          ? _firestore.getPilotAlertStream(
                                              eventId: selectedEvent.id,
                                              sessionId: activeSessionId,
                                              pilotUid: pilotUid,
                                            )
                                          : Stream<Map<String, dynamic>?>.value(
                                              null,
                                            ),
                                      builder: (context, alertSnapshot) {
                                        return _buildPilotAlertTile(
                                          event: selectedEvent,
                                          session: activeSession,
                                          competitor: competitor,
                                          alert: alertSnapshot.data,
                                        );
                                      },
                                    );
                                  },
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
