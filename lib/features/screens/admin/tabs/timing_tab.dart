
import 'package:flutter/material.dart';
import 'package:speed_data/features/models/event_model.dart';
import 'package:speed_data/features/models/race_session_model.dart';
import 'package:speed_data/features/screens/admin/race_control_screen.dart';
import 'package:speed_data/features/services/firestore_service.dart';
import 'package:intl/intl.dart';

class TimingTab extends StatelessWidget {
  const TimingTab({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildSectionHeader('ACTIVE & UPCOMING SESSIONS'),
        Expanded(
          child: StreamBuilder<List<RaceEvent>>(
            stream: FirestoreService().getEventsStream(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(child: Text('Error: ${snapshot.error}'));
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final events = snapshot.data!;
              final now = DateTime.now();
              // Filter for events today or future, scheduling logic can be refined
              final upcomingEvents = events.where((e) => 
                  e.date.isAfter(now.subtract(const Duration(days: 1)))
              ).toList();

              if (upcomingEvents.isEmpty) {
                return const Center(child: Text('No active events. Please create one in Registration.'));
              }

              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: upcomingEvents.length,
                itemBuilder: (context, index) {
                  final event = upcomingEvents[index];
                  // Find active session if any
                  RaceSession? activeSession;
                  try {
                     activeSession = event.sessions.firstWhere((s) => s.status == SessionStatus.active);
                  } catch (e) {
                    activeSession = null;
                  }

                  return Card(
                    color: activeSession != null ? Colors.green.withOpacity(0.1) : null,
                    child: ListTile(
                      leading: Icon(
                        Icons.timer, 
                        size: 40, 
                        color: activeSession != null ? Colors.green : Colors.grey
                      ),
                      title: Text(event.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(DateFormat('yyyy-MM-dd').format(event.date)),
                          if (activeSession != null)
                            Text(
                              'LIVE: ${activeSession.type.name.toUpperCase()}',
                              style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
                            )
                          else
                            const Text('No active session'),
                        ],
                      ),
                      trailing: ElevatedButton(
                        onPressed: () {
                           Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => RaceControlScreen(event: event)),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: activeSession != null ? Colors.green : Colors.blueGrey
                        ),
                        child: Text(activeSession != null ? 'OPEN CONSOLE' : 'PREPARE'),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          title,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Colors.grey,
          ),
        ),
      ),
    );
  }
}
