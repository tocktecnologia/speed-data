import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:speed_data/features/services/firestore_service.dart';
import 'package:speed_data/flutter_flow/nav/nav.dart';
import 'package:speed_data/features/screens/admin/admin_map_view.dart';
import 'package:speed_data/features/screens/admin/create_race_screen.dart';
import 'package:speed_data/features/screens/admin/event_list_screen.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({Key? key}) : super(key: key);

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  final FirestoreService _firestoreService = FirestoreService();
  final User? user = FirebaseAuth.instance.currentUser;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Console'),
        backgroundColor: Colors.black,
      ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            UserAccountsDrawerHeader(
              decoration: const BoxDecoration(color: Colors.black),
              accountName: Text(user?.displayName ?? 'Admin'),
              accountEmail: Text(user?.email ?? ''),
              currentAccountPicture: const CircleAvatar(
                backgroundColor: Colors.white,
                child: Icon(Icons.security, color: Colors.black),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Sign Out'),
              onTap: () async {
                await FirebaseAuth.instance.signOut();
                if (context.mounted) {
                  context.goNamedAuth('Login', context.mounted,
                      ignoreRedirect: true);
                }
              },
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // Create Race Section
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('Race Management',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 20),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.calendar_today),
                        label: const Text('MANAGE EVENTS SCHEDULE'),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (context) => const EventListScreen()),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.black87,
                            padding: const EdgeInsets.symmetric(vertical: 20)),
                      ),
                      const SizedBox(height: 10),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.map),
                        label: const Text('DESIGN NEW RACE TRACK'),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (context) => const CreateRaceScreen()),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.grey[800],
                            padding: const EdgeInsets.symmetric(vertical: 20)),
                      ),
                  ],
                ),
              ),
            ),
          ),

          const Divider(),
          const Padding(
            padding: EdgeInsets.all(8.0),
            child: Text('Active Races',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),

          // List of Races
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _firestoreService.getOpenRaces(),
              builder: (context, snapshot) {
                if (snapshot.hasError) return const Text('Error');
                if (snapshot.connectionState == ConnectionState.waiting)
                  return const Center(child: CircularProgressIndicator());

                final docs = snapshot.data?.docs ?? [];

                return ListView.builder(
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final data = docs[index].data() as Map<String, dynamic>;
                    final raceId = docs[index].id;

                    return Column(
                      children: [
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16.0),
                          child: Divider(color: Colors.black12),
                        ),
                        ListTile(
                          title: Text(data['name']),
                          subtitle: Text('Status: ${data['status']}'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(
                                    Icons.radio_button_checked_sharp,
                                    color: Colors.blue),
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => AdminMapView(
                                        raceId: raceId,
                                        raceName: data['name'],
                                      ),
                                    ),
                                  );
                                },
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                icon:
                                    const Icon(Icons.edit, color: Colors.blue),
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => CreateRaceScreen(
                                        raceId: raceId,
                                        initialData: data,
                                      ),
                                    ),
                                  );
                                },
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                icon:
                                    const Icon(Icons.delete, color: Colors.red),
                                onPressed: () => _confirmDeleteRace(raceId),
                              ),
                            ],
                          ),
                        ),
                      ],
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

  Future<void> _confirmDeleteRace(String raceId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Race?'),
        content: const Text(
            'Are you sure you want to delete this race? This action cannot be undone.'),
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
      await _firestoreService.deleteRace(raceId);
    }
  }

  Future<void> _confirmClearRace(String raceId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Participants?'),
        content: const Text(
            'Are you sure you want to clear all participants from this race? This action cannot be undone and all participant data for this race will be lost.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _firestoreService.clearRaceParticipants(raceId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('All participants cleared successfully.')),
        );
      }
    }
  }
}
