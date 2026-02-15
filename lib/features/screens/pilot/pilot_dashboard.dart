import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:speed_data/features/services/firestore_service.dart';
import 'package:speed_data/flutter_flow/nav/nav.dart';
import 'package:speed_data/features/screens/pilot/active_race_screen.dart';
import 'package:speed_data/features/screens/pilot/gps_test_screen.dart';
import 'package:speed_data/features/screens/pilot/pilot_race_stats_screen.dart';
import 'package:speed_data/features/screens/pilot/pilot_events_screen.dart';
import 'package:speed_data/features/models/event_model.dart';
import 'package:speed_data/features/models/race_session_model.dart';
import 'package:speed_data/theme/speed_data_theme.dart';

class PilotDashboard extends StatefulWidget {
  const PilotDashboard({Key? key}) : super(key: key);

  @override
  State<PilotDashboard> createState() => _PilotDashboardState();
}

class _PilotDashboardState extends State<PilotDashboard> {
  bool _autoNavigated = false;

  DateTime _eventEndDate(RaceEvent event) {
    if (event.endDate != null) {
      final localEnd = event.endDate!.toLocal();
      final isMidnight = localEnd.hour == 0 &&
          localEnd.minute == 0 &&
          localEnd.second == 0 &&
          localEnd.millisecond == 0;
      if (isMidnight) {
        return DateTime(
            localEnd.year, localEnd.month, localEnd.day, 23, 59, 59, 999);
      }
      return localEnd;
    }
    final local = event.date.toLocal();
    return DateTime(local.year, local.month, local.day, 23, 59, 59, 999);
  }

  bool _isEventActiveNow(RaceEvent event, DateTime now) {
    final nowLocal = now.toLocal();
    final eventStartLocal = event.date.toLocal();
    final eventStart = DateTime(
        eventStartLocal.year, eventStartLocal.month, eventStartLocal.day);
    final eventEnd = _eventEndDate(event).toLocal();
    if (nowLocal.isBefore(eventStart)) return false;
    return nowLocal.isBefore(eventEnd) || nowLocal.isAtSameMomentAs(eventEnd);
  }

  RaceSession? _findActiveSession(RaceEvent event) {
    try {
      return event.sessions.firstWhere((s) => s.status == SessionStatus.active);
    } catch (_) {
      return null;
    }
  }

  RaceSession? _findNextSession(RaceEvent event, DateTime now) {
    final sessions = List<RaceSession>.from(event.sessions)
      ..sort((a, b) => a.scheduledTime.compareTo(b.scheduledTime));
    for (final session in sessions) {
      if (session.scheduledTime.isAfter(now) ||
          session.scheduledTime.isAtSameMomentAs(now)) {
        return session;
      }
    }
    return null;
  }

  String _formatDurationUntil(DateTime from, DateTime to) {
    final diff = to.difference(from);
    if (diff.isNegative) return 'agora';
    final hours = diff.inHours;
    final minutes = diff.inMinutes.remainder(60);
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    return '${minutes}m';
  }

  String _formatSessionStartTime(DateTime dateTime) {
    final local = dateTime.toLocal();
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  String _sessionDisplayName(RaceSession session) {
    if (session.name.isNotEmpty) return session.name;
    return session.type.name.toUpperCase();
  }

  Widget _buildEventHighlightCard(
    BuildContext context, {
    required FirestoreService firestoreService,
    required RaceEvent event,
  }) {
    final now = DateTime.now();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final flagColors = theme.extension<SpeedDataColors>();
    final activeSession = _findActiveSession(event);
    final nextSession = activeSession ?? _findNextSession(event, now);
    final nextSessionName =
        nextSession != null ? _sessionDisplayName(nextSession) : 'No sessions';
    final nextSessionStartTime = nextSession != null
        ? _formatSessionStartTime(nextSession.scheduledTime)
        : '--';
    final hasActiveSession = activeSession != null;
    final cardColor = hasActiveSession
        ? (flagColors?.flagGreen ?? scheme.secondary)
        : (flagColors?.flagYellow ?? scheme.surfaceVariant);
    final textColor = hasActiveSession
        ? (flagColors?.onFlagGreen ?? scheme.onSecondary)
        : (flagColors?.onFlagYellow ?? scheme.onSurfaceVariant);

    return FutureBuilder<Map<String, dynamic>?>(
      future: firestoreService.getRace(event.trackId),
      builder: (context, snapshot) {
        final trackName = snapshot.data?['name'] ?? 'Track';
        return InkWell(
          onTap: hasActiveSession
              ? () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ActiveRaceScreen(
                        raceId: event.trackId,
                        userId: FirebaseAuth.instance.currentUser?.uid ?? '',
                        raceName: event.name,
                        eventId: event.id,
                      ),
                    ),
                  );
                }
              : null,
          child: Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: cardColor,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hasActiveSession
                        ? 'Session is live'
                        : 'Registered for active event',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: textColor),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${event.name} • $trackName',
                    style: TextStyle(color: textColor.withOpacity(0.9)),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    hasActiveSession
                        ? 'Live: ${_sessionDisplayName(activeSession!)}'
                        : 'Next: $nextSessionName • $nextSessionStartTime',
                    style: TextStyle(color: textColor.withOpacity(0.9)),
                  ),
                  const SizedBox(height: 12),
                  if (hasActiveSession)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('GO TO LIVE TIMER'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: textColor,
                          foregroundColor: cardColor,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ActiveRaceScreen(
                                raceId: event.trackId,
                                userId:
                                    FirebaseAuth.instance.currentUser?.uid ??
                                        '',
                                raceName: event.name,
                                eventId: event.id,
                              ),
                            ),
                          );
                        },
                      ),
                    )
                  else
                    Text(
                      'Be ready. Waiting for the organizer to start a session.',
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: textColor),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<List<RaceEvent>> _loadActiveRegisteredEvents(
    FirestoreService firestoreService,
    List<RaceEvent> events,
    String uid,
  ) async {
    final now = DateTime.now();
    final activeEvents =
        events.where((e) => _isEventActiveNow(e, now)).toList();
    final checks = await Future.wait(activeEvents.map((event) async {
      final isRegistered =
          await firestoreService.isUserRegisteredInEvent(event.id, uid);
      return isRegistered ? event : null;
    }));
    return checks.whereType<RaceEvent>().toList();
  }

  Widget _buildDashboardBody(
    BuildContext context, {
    required FirestoreService firestoreService,
    required User? user,
  }) {
    return StreamBuilder<List<RaceEvent>>(
      stream: firestoreService.getEventsStream(),
      builder: (context, eventsSnapshot) {
        if (eventsSnapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final events = eventsSnapshot.data ?? [];

        return FutureBuilder<List<RaceEvent>>(
          future: user == null
              ? Future.value([])
              : _loadActiveRegisteredEvents(
                  firestoreService,
                  events,
                  user.uid,
                ),
          builder: (context, activeEventsSnapshot) {
            final activeEvents = activeEventsSnapshot.data ?? [];
            final activeEvent = activeEvents.isNotEmpty
                ? (activeEvents..sort((a, b) => a.date.compareTo(b.date)))
                : null;

            final anyActive = activeEvent != null
                ? activeEvent.any((event) =>
                    event.sessions.any((s) => s.status == SessionStatus.active))
                : false;

            if (!_autoNavigated && activeEvent != null) {
              final eventWithActiveSession = activeEvent.firstWhere(
                (event) =>
                    event.sessions.any((s) => s.status == SessionStatus.active),
                orElse: () => activeEvent.first,
              );
              final hasActiveSession = eventWithActiveSession.sessions
                  .any((s) => s.status == SessionStatus.active);
              if (hasActiveSession) {
                _autoNavigated = true;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ActiveRaceScreen(
                        raceId: eventWithActiveSession.trackId,
                        userId: user?.uid ?? '',
                        raceName: eventWithActiveSession.name,
                        eventId: eventWithActiveSession.id,
                      ),
                    ),
                  );
                });
              }
            } else if (activeEvent != null) {
              if (!anyActive) {
                _autoNavigated = false;
              }
            }

            return StreamBuilder<QuerySnapshot>(
              stream: firestoreService.getOpenRaces(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(child: Text('Error loading races'));
                }

                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final docs = snapshot.data?.docs ?? [];
                if (docs.isEmpty) {
                  return const Center(child: Text('No active races found.'));
                }

                return ListView(
                  children: [
                    if (activeEvent != null && activeEvent.isNotEmpty)
                      _buildEventHighlightCard(
                        context,
                        firestoreService: firestoreService,
                        event: activeEvent.first,
                      ),
                    const Padding(
                      padding:
                          EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Text(
                        'Practice tracks',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                    if (anyActive)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 4),
                        child: Text(
                          'Practice tracks are disabled while your active session is running.',
                          style: TextStyle(color: Theme.of(context).hintColor),
                        ),
                      ),
                    AbsorbPointer(
                      absorbing: anyActive,
                      child: Opacity(
                        opacity: anyActive ? 0.4 : 1,
                        child: Column(
                          children: [
                            ...docs.map((doc) {
                              final data = doc.data() as Map<String, dynamic>;
                              final raceId = doc.id;
                              final raceName = data['name'] ?? 'Unnamed Race';
                              return _buildRaceCard(
                                context: context,
                                firestoreService: firestoreService,
                                user: user,
                                raceId: raceId,
                                raceName: raceName,
                              );
                            }),
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
    );
  }

  Widget _buildRaceCard({
    required BuildContext context,
    required FirestoreService firestoreService,
    required User? user,
    required String raceId,
    required String raceName,
  }) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        title:
            Text(raceName, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: const Text('Status: Open for registration'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Test GPS',
              icon: const Icon(Icons.gps_fixed, color: Colors.green),
              onPressed: () async {
                if (user == null) return;

                // Fetch User Profile
                int finalColor = 0xFF0000FF; // Default Blue
                String finalName =
                    user.displayName ?? 'Pilot ${user.uid.substring(0, 4)}';

                try {
                  final profile =
                      await firestoreService.getUserProfile(user.uid);
                  if (profile != null) {
                    if (profile['name'] != null) {
                      finalName = profile['name'];
                    }
                    if (profile['color'] != null) {
                      if (profile['color'] is int) {
                        finalColor = profile['color'];
                      } else if (profile['color'] is String) {
                        finalColor =
                            int.tryParse(profile['color']) ?? finalColor;
                      }
                    }
                  }
                } catch (e) {
                  print('Error fetching profile: $e');
                }

                // Join Race
                await firestoreService.joinRace(
                  raceId,
                  user.uid,
                  finalName,
                  finalColor,
                );
                if (context.mounted) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => GpsTestScreen(
                        raceId: raceId,
                        userId: user.uid,
                        raceName: raceName,
                      ),
                    ),
                  );
                }
              },
            ),
            IconButton(
              tooltip: 'Stats',
              icon: const Icon(Icons.bar_chart, color: Colors.orange),
              onPressed: () {
                if (user == null) return;

                showModalBottomSheet(
                  context: context,
                  backgroundColor: Colors.grey[900],
                  shape: const RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.vertical(top: Radius.circular(20))),
                  builder: (context) {
                    return Container(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("Select Session",
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold)),
                          const SizedBox(height: 10),
                          ListTile(
                            leading: const Icon(Icons.play_circle_outline,
                                color: Colors.greenAccent),
                            title: const Text("Current / Active Session",
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold)),
                            trailing: const Icon(Icons.arrow_forward_ios,
                                color: Colors.white, size: 14),
                            onTap: () {
                              Navigator.pop(context);
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => PilotRaceStatsScreen(
                                    raceId: raceId,
                                    userId: user.uid,
                                    raceName: raceName,
                                    historySessionId: null,
                                  ),
                                ),
                              );
                            },
                          ),
                          const Divider(color: Colors.grey),
                          Expanded(
                            child: StreamBuilder<QuerySnapshot>(
                              stream: firestoreService.getHistorySessions(
                                  raceId, user.uid),
                              builder: (context, snapshot) {
                                if (snapshot.connectionState ==
                                    ConnectionState.waiting) {
                                  return const Center(
                                      child: CircularProgressIndicator());
                                }
                                if (!snapshot.hasData ||
                                    snapshot.data!.docs.isEmpty) {
                                  return const Center(
                                      child: Text("No history sessions found",
                                          style:
                                              TextStyle(color: Colors.white)));
                                }

                                final sessions = snapshot.data!.docs;
                                return ListView.builder(
                                  itemCount: sessions.length,
                                  itemBuilder: (context, index) {
                                    final session = sessions[index].data()
                                        as Map<String, dynamic>;
                                    final sessionId = sessions[index].id;
                                    final archivedAt =
                                        session['archived_at'] as Timestamp?;
                                    final dateStr = archivedAt != null
                                        ? archivedAt
                                            .toDate()
                                            .toString()
                                            .split('.')[0]
                                        : "Unknown Date";

                                    return ListTile(
                                      title: Text("Session: $dateStr",
                                          style: const TextStyle(
                                              color: Colors.white)),
                                      subtitle: Text(sessionId,
                                          style: const TextStyle(
                                              color: Colors.grey,
                                              fontSize: 10)),
                                      trailing: const Icon(
                                          Icons.arrow_forward_ios,
                                          color: Colors.white,
                                          size: 14),
                                      onTap: () {
                                        Navigator.pop(context);
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) =>
                                                PilotRaceStatsScreen(
                                              raceId: raceId,
                                              userId: user.uid,
                                              raceName: raceName,
                                              historySessionId: sessionId,
                                            ),
                                          ),
                                        );
                                      },
                                    );
                                  },
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
            IconButton(
              tooltip: 'Join & Start',
              icon: const Icon(Icons.flag, color: Colors.blueAccent),
              onPressed: () async {
                if (user == null) return;

                // Fetch User Profile
                int finalColor = 0xFF0000FF; // Default Blue
                String finalName =
                    user.displayName ?? 'Pilot ${user.uid.substring(0, 4)}';

                try {
                  final profile =
                      await firestoreService.getUserProfile(user.uid);
                  if (profile != null) {
                    if (profile['name'] != null) {
                      finalName = profile['name'];
                    }
                    if (profile['color'] != null) {
                      if (profile['color'] is int) {
                        finalColor = profile['color'];
                      } else if (profile['color'] is String) {
                        finalColor =
                            int.tryParse(profile['color']) ?? finalColor;
                      }
                    }
                  }
                } catch (e) {
                  print('Error fetching profile: $e');
                }

                // Join Race
                await firestoreService.joinRace(
                  raceId,
                  user.uid,
                  finalName,
                  finalColor,
                );

                // Navigate
                if (context.mounted) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ActiveRaceScreen(
                        raceId: raceId,
                        userId: user.uid,
                        raceName: raceName,
                      ),
                    ),
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final FirestoreService firestoreService = FirestoreService();
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Available Races'),
        backgroundColor: Colors.black,
      ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            UserAccountsDrawerHeader(
              decoration: const BoxDecoration(color: Colors.black),
              accountName: Text(user?.displayName ?? 'Pilot'),
              accountEmail: Text(user?.email ?? ''),
              currentAccountPicture: const CircleAvatar(
                backgroundColor: Colors.white,
                child: Icon(Icons.person, color: Colors.black),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Sign Out'),
              onTap: () async {
                await FirebaseAuth.instance.signOut();
                if (context.mounted) {
                  // Explicitly navigate to login
                  context.goNamedAuth('Login', context.mounted,
                      ignoreRedirect: true);
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.event),
              title: const Text('Eventos'),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const PilotEventsScreen(),
                  ),
                );
              },
            ),
          ],
        ),
      ),
      body: _buildDashboardBody(
        context,
        firestoreService: firestoreService,
        user: user,
      ),
    );
  }
}
