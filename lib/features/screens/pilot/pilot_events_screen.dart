import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:speed_data/features/models/event_model.dart';
import 'package:speed_data/features/services/firestore_service.dart';
import 'package:speed_data/features/screens/pilot/pilot_event_schedule_screen.dart';

class PilotEventsScreen extends StatefulWidget {
  const PilotEventsScreen({Key? key}) : super(key: key);

  @override
  State<PilotEventsScreen> createState() => _PilotEventsScreenState();
}

class _PilotEventsScreenState extends State<PilotEventsScreen> {
  final FirestoreService _firestoreService = FirestoreService();

  Future<List<_EventWithReg>> _loadRegistrations(
      List<RaceEvent> events, String uid) async {
    final checks = await Future.wait(events.map((event) async {
      final isRegistered =
          await _firestoreService.isUserRegisteredInEvent(event.id, uid);
      return _EventWithReg(event: event, isRegistered: isRegistered);
    }));
    return checks;
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('User not signed in.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Eventos'),
        backgroundColor: Colors.black,
      ),
      body: StreamBuilder<List<RaceEvent>>(
        stream: _firestoreService.getEventsStream(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('Erro ao carregar eventos'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final events = snapshot.data!
            ..sort((a, b) => a.date.compareTo(b.date));
          if (events.isEmpty) {
            return const Center(child: Text('Nenhum evento encontrado.'));
          }

          return FutureBuilder<List<_EventWithReg>>(
            future: _loadRegistrations(events, user.uid),
            builder: (context, regSnapshot) {
              if (!regSnapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final entries = regSnapshot.data!;
              final registered = entries.where((e) => e.isRegistered).toList();
              final others = entries.where((e) => !e.isRegistered).toList();

              return ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  _buildSection(
                    title: 'Meus eventos',
                    entries: registered,
                  ),
                  const SizedBox(height: 12),
                  _buildSection(
                    title: 'Outros eventos',
                    entries: others,
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required List<_EventWithReg> entries,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        if (entries.isEmpty)
          const Text('Nenhum evento nesta categoria.',
              style: TextStyle(color: Colors.black54)),
        ...entries.map((entry) => _buildEventCard(entry)),
      ],
    );
  }

  Widget _buildEventCard(_EventWithReg entry) {
    final event = entry.event;
    final dateStr = event.date.toString().split(' ').first;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(event.name,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text('Data: $dateStr'),
        trailing: Icon(
          entry.isRegistered ? Icons.check_circle : Icons.event,
          color: entry.isRegistered ? Colors.green : Colors.blueGrey,
        ),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => PilotEventScheduleScreen(
                eventId: event.id,
                eventName: event.name,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _EventWithReg {
  final RaceEvent event;
  final bool isRegistered;

  const _EventWithReg({required this.event, required this.isRegistered});
}
