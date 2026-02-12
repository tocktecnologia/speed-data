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
                      IconButton(
                        tooltip: 'Test GPS',
                        icon: const Icon(Icons.gps_fixed, color: Colors.green),
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
                                borderRadius: BorderRadius.vertical(
                                    top: Radius.circular(20))),
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
                                      leading: const Icon(
                                          Icons.play_circle_outline,
                                          color: Colors.greenAccent),
                                      title: const Text(
                                          "Current / Active Session",
                                          style: TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold)),
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
                                              historySessionId: null,
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                    const Divider(color: Colors.grey),
                                    Expanded(
                                      child: StreamBuilder<QuerySnapshot>(
                                        stream:
                                            firestoreService.getHistorySessions(
                                                raceId, user.uid),
                                        builder: (context, snapshot) {
                                          if (snapshot.connectionState ==
                                              ConnectionState.waiting) {
                                            return const Center(
                                                child:
                                                    CircularProgressIndicator());
                                          }
                                          if (!snapshot.hasData ||
                                              snapshot.data!.docs.isEmpty) {
                                            return const Center(
                                                child: Text(
                                                    "No history sessions found",
                                                    style: TextStyle(
                                                        color: Colors.white)));
                                          }

                                          final sessions = snapshot.data!.docs;
                                          return ListView.builder(
                                            itemCount: sessions.length,
                                            itemBuilder: (context, index) {
                                              final session =
                                                  sessions[index].data()
                                                      as Map<String, dynamic>;
                                              final sessionId =
                                                  sessions[index].id;
                                              final archivedAt =
                                                  session['archived_at']
                                                      as Timestamp?;
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
                                                  Navigator.pop(
                                                      context); // Close modal
                                                  Navigator.push(
                                                    context,
                                                    MaterialPageRoute(
                                                      builder: (context) =>
                                                          PilotRaceStatsScreen(
                                                        raceId: raceId,
                                                        userId: user.uid,
                                                        raceName: raceName,
                                                        historySessionId:
                                                            sessionId,
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
