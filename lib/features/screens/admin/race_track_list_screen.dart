
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:speed_data/features/screens/admin/create_race_screen.dart';
import 'package:intl/intl.dart';

class RaceTrackListScreen extends StatefulWidget {
  const RaceTrackListScreen({Key? key}) : super(key: key);

  @override
  State<RaceTrackListScreen> createState() => _RaceTrackListScreenState();
}

class _RaceTrackListScreenState extends State<RaceTrackListScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  late Stream<QuerySnapshot> _tracksStream;

  Future<void> _deleteTrack(String trackId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Track?'),
        content: const Text(
            'Are you sure you want to delete this track? This action cannot be undone.'),
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
      try {
        await _db.collection('races').doc(trackId).delete();
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Track deleted successfully')));
      } catch (e) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error deleting track: $e')));
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _refreshTracks();
  }

  Future<void> _refreshTracks() async {
    setState(() {
      _tracksStream = _db
          .collection('races')
          .orderBy('created_at', descending: true)
          .snapshots();
    });
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Race Tracks'),
          backgroundColor: Colors.black,
          bottom: const TabBar(
            indicatorColor: Colors.amber,
            tabs: [
              Tab(text: 'MY TRACKS'),
              Tab(text: 'EXPLORE'),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton(
          backgroundColor: Colors.black,
          child: const Icon(Icons.add),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const CreateRaceScreen()),
            );
          },
        ),
        body: StreamBuilder<QuerySnapshot>(
          stream: _tracksStream,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(child: Text('Error: ${snapshot.error}'));
            }
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final docs = snapshot.data!.docs;
            final myTracks = docs.where((doc) {
              final data = doc.data() as Map<String, dynamic>;
              return data['creator_id'] == currentUser?.uid;
            }).toList();

            final exploreTracks = docs.where((doc) {
              final data = doc.data() as Map<String, dynamic>;
              return data['creator_id'] != currentUser?.uid;
            }).toList();

            return TabBarView(
              children: [
                _buildTrackList(myTracks, true),
                _buildTrackList(exploreTracks, false),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildTrackList(List<QueryDocumentSnapshot> docs, bool isMyTrack) {
    if (docs.isEmpty) {
      return RefreshIndicator(
        onRefresh: _refreshTracks,
        child: ListView(
          children: [
            const SizedBox(height: 100),
            Center(
              child: Text(
                isMyTrack
                    ? 'You haven\'t created any tracks yet.'
                    : 'No other tracks found.',
                style: const TextStyle(color: Colors.grey),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refreshTracks,
      child: ListView.builder(
        itemCount: docs.length,
        itemBuilder: (context, index) {
          final data = docs[index].data() as Map<String, dynamic>;
          final trackId = docs[index].id;
          final name = data['name'] ?? 'Unnamed Track';
          final createdAt = data['created_at'] != null
              ? (data['created_at'] as Timestamp).toDate()
              : null;
          final checkpoints = (data['checkpoints'] as List?)?.length ?? 0;

          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: ListTile(
              leading: const CircleAvatar(
                backgroundColor: Colors.black,
                child: Icon(Icons.map, color: Colors.white),
              ),
              title: Text(name,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(
                'Checkpoints: $checkpoints${createdAt != null ? '\nCreated: ${DateFormat('yyyy-MM-dd').format(createdAt)}' : ''}',
              ),
              isThreeLine: createdAt != null,
              trailing: isMyTrack
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit, color: Colors.blue),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (context) => CreateRaceScreen(
                                      raceId: trackId, initialData: data)),
                            );
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () => _deleteTrack(trackId),
                        ),
                      ],
                    )
                  : IconButton(
                      icon: const Icon(Icons.visibility),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => CreateRaceScreen(
                              raceId: trackId,
                              initialData: data,
                              readOnly: true,
                            ),
                          ),
                        );
                      },
                      tooltip: 'View Track',
                    ),
            ),
          );
        },
      ),
    );
  }
}
