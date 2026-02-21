import 'package:flutter/material.dart';
import 'package:speed_data/features/models/competitor_model.dart';
import 'package:speed_data/features/models/event_model.dart';
import 'package:speed_data/features/models/race_session_model.dart';
import 'package:speed_data/features/screens/pilot/lap_times_screen.dart';
import 'package:speed_data/features/services/firestore_service.dart';

class AdminSessionLapTimesScreen extends StatelessWidget {
  final RaceEvent event;
  final RaceSession session;

  const AdminSessionLapTimesScreen({
    super.key,
    required this.event,
    required this.session,
  });

  String _sessionTitle(RaceSession value) {
    if (value.name.trim().isNotEmpty) return value.name.trim();
    return value.type.name.toUpperCase();
  }

  String _competitorName(Competitor competitor) {
    final name = competitor.name.trim();
    if (name.isNotEmpty) return name;
    final label = competitor.label.trim();
    if (label.isNotEmpty) return label;
    final number = competitor.number.trim();
    if (number.isNotEmpty) return 'Car #$number';
    return 'Competitor';
  }

  @override
  Widget build(BuildContext context) {
    final firestore = FirestoreService();
    final sessionTitle = _sessionTitle(session);

    return Scaffold(
      appBar: AppBar(
        title: Text('Lap Times - $sessionTitle'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${event.name} • Select participant',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<List<Competitor>>(
              stream: firestore.getCompetitorsStream(event.id),
              builder: (context, snapshot) {
                if (!snapshot.hasData &&
                    snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final competitors = (snapshot.data ?? const <Competitor>[])
                    .where((competitor) => competitor.uid.trim().isNotEmpty)
                    .toList(growable: false)
                  ..sort((a, b) {
                    final byNumber = a.number.compareTo(b.number);
                    if (byNumber != 0) return byNumber;
                    return _competitorName(a).compareTo(_competitorName(b));
                  });

                if (competitors.isEmpty) {
                  return const Center(
                    child: Text(
                      'No participants with linked user found in this event.',
                    ),
                  );
                }

                return ListView.separated(
                  itemCount: competitors.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final competitor = competitors[index];
                    final number = competitor.number.trim();
                    final subtitle = [
                      if (number.isNotEmpty) 'Car #$number',
                      'UID: ${competitor.uid}',
                    ].join(' • ');

                    return ListTile(
                      leading: CircleAvatar(
                        child: Text(
                          number.isEmpty ? '?' : number,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      title: Text(
                        _competitorName(competitor),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => LapTimesScreen(
                              raceId: event.trackId,
                              userId: competitor.uid,
                              raceName:
                                  '${event.name} • ${_competitorName(competitor)}',
                              eventId: event.id,
                              initialSessionId: session.id,
                              fixedSessionLabel: sessionTitle,
                              lockSessionSelection: true,
                              sessionIdsStreamOverride:
                                  Stream<List<String>>.value(
                                      <String>[session.id]),
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
  }
}
