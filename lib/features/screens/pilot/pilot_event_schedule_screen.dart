import 'package:flutter/material.dart';
import 'package:speed_data/features/models/event_model.dart';
import 'package:speed_data/features/models/race_session_model.dart';
import 'package:speed_data/features/services/firestore_service.dart';

class PilotEventScheduleScreen extends StatelessWidget {
  final String eventId;
  final String eventName;

  const PilotEventScheduleScreen({
    Key? key,
    required this.eventId,
    required this.eventName,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final FirestoreService firestoreService = FirestoreService();

    return Scaffold(
      appBar: AppBar(
        title: Text(eventName),
        backgroundColor: Colors.black,
      ),
      body: StreamBuilder<RaceEvent>(
        stream: firestoreService.getEventStream(eventId),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('Erro ao carregar cronograma'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final event = snapshot.data!;
          final sessions = List<RaceSession>.from(event.sessions)
            ..sort((a, b) => a.scheduledTime.compareTo(b.scheduledTime));
          final groupNameById = {
            for (final group in event.groups) group.id: group.name
          };

          if (sessions.isEmpty) {
            return const Center(child: Text('Nenhuma prova cadastrada.'));
          }

          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: sessions.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final session = sessions[index];
              final timeStr = _formatSessionTime(session.scheduledTime);
              final groupName = groupNameById[session.groupId] ?? 'Grupo';
              final status = _statusLabel(session.status);
              final statusColor = _statusColor(session.status);
              final title =
                  session.name.isNotEmpty ? session.name : session.type.name;

              return ListTile(
                title: Text('$timeStr • $title',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(groupName),
                trailing: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: statusColor),
                  ),
                  child: Text(
                    status,
                    style: TextStyle(
                        color: statusColor, fontWeight: FontWeight.bold),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  String _formatSessionTime(DateTime dateTime) {
    final h = dateTime.hour.toString().padLeft(2, '0');
    final m = dateTime.minute.toString().padLeft(2, '0');
    final d = dateTime.day.toString().padLeft(2, '0');
    final mo = dateTime.month.toString().padLeft(2, '0');
    return '$d/$mo $h:$m';
  }

  String _statusLabel(SessionStatus status) {
    switch (status) {
      case SessionStatus.scheduled:
        return 'AGENDADA';
      case SessionStatus.active:
        return 'ATIVA';
      case SessionStatus.finished:
        return 'ENCERRADA';
    }
  }

  Color _statusColor(SessionStatus status) {
    switch (status) {
      case SessionStatus.scheduled:
        return Colors.blueGrey;
      case SessionStatus.active:
        return Colors.green;
      case SessionStatus.finished:
        return Colors.grey;
    }
  }
}
