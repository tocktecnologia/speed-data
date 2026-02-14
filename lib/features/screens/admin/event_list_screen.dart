
import 'package:flutter/material.dart';
import 'package:speed_data/features/models/event_model.dart';
import 'package:speed_data/features/screens/admin/create_event_screen.dart';
import 'package:speed_data/features/screens/admin/race_control_screen.dart';
import 'package:speed_data/features/screens/admin/event_registration_screen.dart'; // Will implement next
import 'package:speed_data/features/services/firestore_service.dart';
import 'package:intl/intl.dart';

class EventListScreen extends StatefulWidget {
  const EventListScreen({Key? key}) : super(key: key);

  @override
  State<EventListScreen> createState() => _EventListScreenState();
}

class _EventListScreenState extends State<EventListScreen> {
  final FirestoreService _firestoreService = FirestoreService();

  void _deleteEvent(String eventId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Event?'),
        content: const Text('Are you sure you want to delete this event?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _firestoreService.deleteEvent(eventId);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Events Schedule'),
        backgroundColor: Colors.black,
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.black,
        child: const Icon(Icons.add),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const CreateEventScreen()),
          );
        },
      ),
      body: StreamBuilder<List<RaceEvent>>(
        stream: _firestoreService.getEventsStream(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final events = snapshot.data!;

          if (events.isEmpty) {
             return const Center(child: Text('No events scheduled.'));
          }

          return ListView.builder(
            itemCount: events.length,
            itemBuilder: (context, index) {
              final event = events[index];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: ListTile(
                  title: Text(event.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Date: ${DateFormat('yyyy-MM-dd').format(event.date)}'),
                      Text('Sessions: ${event.sessions.map((s) => s.type.name.toUpperCase()).join(", ")}'),
                    ],
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                       IconButton(
                        icon: const Icon(Icons.play_arrow, color: Colors.green),
                        tooltip: 'Race Control',
                        onPressed: () {
                           // Navigate to Race Control
                           Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => RaceControlScreen(event: event)),
                          );
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit, color: Colors.blue),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (context) =>
                                    EventRegistrationScreen(event: event)),
                          );
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _deleteEvent(event.id),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
