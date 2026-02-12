import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:speed_data/features/services/firestore_service.dart';
import 'package:speed_data/flutter_flow/nav/nav.dart';
import 'package:speed_data/features/screens/pilot/active_race_screen.dart';
import 'package:speed_data/features/screens/pilot/gps_test_screen.dart';
import 'package:speed_data/features/screens/pilot/pilot_race_stats_screen.dart';

class PilotDashboard extends StatelessWidget {
  const PilotDashboard({Key? key}) : super(key: key);

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
          ],
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: firestoreService.getOpenRaces(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('Error loading races'));
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data?.docs ?? [];
          print('Found ${docs.length} races'); // Debug
          if (docs.isEmpty) {
            return const Center(child: Text('No active races found.'));
          }

          return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final data = docs[index].data() as Map<String, dynamic>;
              final raceId = docs[index].id;
              final raceName = data['name'] ?? 'Unnamed Race';

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                child: ListTile(
                  title: Text(raceName,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: const Text('Status: Open for registration'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton(
                        onPressed: () async {
                          if (user == null) return;

                          // Fetch User Profile
                          int finalColor = 0xFF0000FF; // Default Blue
                          String finalName = user.displayName ??
                              'Pilot ${user.uid.substring(0, 4)}';

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
                                  finalColor = int.tryParse(profile['color']) ??
                                      finalColor;
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
                        },
                        child: const Text('TEST GPS'),
                      ),
                      TextButton(
                        onPressed: () {
                          if (user == null) return;
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => PilotRaceStatsScreen(
                                raceId: raceId,
                                userId: user.uid,
                                raceName: raceName,
                              ),
                            ),
                          );
                        },
                        child: const Text('STATS'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () async {
                          if (user == null) return;

                          // Fetch User Profile
                          int finalColor = 0xFF0000FF; // Default Blue
                          String finalName = user.displayName ??
                              'Pilot ${user.uid.substring(0, 4)}';

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
                                  finalColor = int.tryParse(profile['color']) ??
                                      finalColor;
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
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blueAccent,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('JOIN & START'),
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
