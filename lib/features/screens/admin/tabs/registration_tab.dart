
import 'package:flutter/material.dart';
import 'package:speed_data/features/screens/admin/event_list_screen.dart';

class RegistrationTab extends StatelessWidget {
  const RegistrationTab({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildSectionHeader('DATABASE'),
        Card(
          child: ListTile(
            leading: const Icon(Icons.people, size: 40, color: Colors.blue),
            title: const Text('Drivers & Teams', style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: const Text('Manage competitor database and transponders.'),
            trailing: const Icon(Icons.arrow_forward_ios),
            onTap: () {
               // Placeholder for dedicated driver management screen if we build one
               // For now, we can show a snackbar or navigate to a dummy screen
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Driver Database Management Coming Soon')),
                );
            },
          ),
        ),
        const SizedBox(height: 24),
        _buildSectionHeader('EVENTS & SCHEDULE'),
         Card(
          child: ListTile(
            leading: const Icon(Icons.calendar_month, size: 40, color: Colors.green),
            title: const Text('Event Management', style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: const Text('Create events, schedule sessions, and assign run groups.'),
            trailing: const Icon(Icons.arrow_forward_ios),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const EventListScreen()),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0, left: 4.0),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: Colors.grey,
        ),
      ),
    );
  }
}
