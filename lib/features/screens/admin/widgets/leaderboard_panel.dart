import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:speed_data/features/services/firestore_service.dart';
import 'dart:async';

class LeaderboardPanel extends StatefulWidget {
  final String raceId;
  final List<dynamic> checkpoints;

  const LeaderboardPanel({
    Key? key,
    required this.raceId,
    required this.checkpoints,
  }) : super(key: key);

  @override
  State<LeaderboardPanel> createState() => _LeaderboardPanelState();
}

class PilotStats {
  final String uid;
  final String displayName;
  final double averageLapTime; // in ms
  final double bestLapTime; // in ms
  final int completedLaps;
  final int currentLapNumber;
  final Map<String, dynamic> currentPoints;
  // Instead of passing strings, let's keep it simple or update the logic where it's generated.
  // The existing code passes `intervalStrings`. I'll update how they are generated.
  final List<String> intervalStrings;

  PilotStats({
    required this.uid,
    required this.displayName,
    required this.averageLapTime,
    required this.bestLapTime,
    required this.completedLaps,
    required this.currentLapNumber,
    required this.currentPoints,
    required this.intervalStrings,
  });
}

class _LeaderboardPanelState extends State<LeaderboardPanel> {
  final FirestoreService _firestoreService = FirestoreService();
  StreamSubscription? _participantsSubscription;
  final Map<String, StreamSubscription> _sessionSubscriptions = {};
  final Map<String, StreamSubscription> _lapSubscriptions = {};
  final Map<String, PilotStats> _stats = {};

  String? _expandedPilotId;

  @override
  void initState() {
    super.initState();
    _subscribeParticipants();
  }

  @override
  void dispose() {
    _participantsSubscription?.cancel();
    for (var sub in _sessionSubscriptions.values) sub.cancel();
    for (var sub in _lapSubscriptions.values) sub.cancel();
    super.dispose();
  }

  void _subscribeParticipants() {
    _participantsSubscription =
        _firestoreService.getRaceLocations(widget.raceId).listen((snapshot) {
      for (var doc in snapshot.docs) {
        final uid = doc.id;
        final data = doc.data() as Map<String, dynamic>;
        final displayName =
            data['display_name'] ?? 'Pilot ${uid.substring(0, 4)}';

        if (!_sessionSubscriptions.containsKey(uid)) {
          _subscribeToPilotSession(uid, displayName);
        }
      }
    });
  }

  void _subscribeToPilotSession(String uid, String displayName) {
    _sessionSubscriptions[uid] =
        _firestoreService.getLaps(widget.raceId, uid).listen((snapshot) {
      if (snapshot.docs.isNotEmpty) {
        _processLaps(uid, displayName, snapshot.docs);
      }
    });
  }

  void _processLaps(
      String uid, String displayName, List<QueryDocumentSnapshot> docs) {
    if (docs.isEmpty) return;

    double totalTime = 0;
    double bestTime = double.infinity;
    int count = 0;

    // Calculate average lap time and find best lap
    for (var doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      if (data.containsKey('totalLapTime')) {
        final t = (data['totalLapTime'] as num).toDouble();
        totalTime += t;
        if (t < bestTime) bestTime = t;
        count++;
      }
    }

    double average = count > 0 ? totalTime / count : 0;
    double best = bestTime == double.infinity ? 0 : bestTime;

    // Latest lap info (docs are ordered by number descending in the query)
    final latestLapData = docs.first.data() as Map<String, dynamic>;
    final currentPoints =
        latestLapData['points'] as Map<String, dynamic>? ?? {};
    final lapNumber = latestLapData['number'] as int? ?? 1;

    // Calculate Intervals for the latest lap
    List<String> intervals = [];
    if (widget.checkpoints.isNotEmpty) {
      // Checkpoints usually 0 to N-1
      // Interval 1: cp_0 -> cp_1
      for (int i = 0; i < widget.checkpoints.length - 1; i++) {
        final k1 = 'cp_$i';
        final k2 = 'cp_${i + 1}';

        if (currentPoints.containsKey(k1) && currentPoints.containsKey(k2)) {
          final t1 = currentPoints[k1]['timestamp'] as int;
          final t2 = currentPoints[k2]['timestamp'] as int;
          final diff = t2 - t1;
          intervals.add(_formatDuration(diff));
        } else {
          intervals.add("-"); // Or "" to hide?
        }
      }
    }

    if (mounted) {
      setState(() {
        _stats[uid] = PilotStats(
          uid: uid,
          displayName: displayName,
          averageLapTime: average,
          bestLapTime: best,
          completedLaps: count,
          currentLapNumber: lapNumber,
          currentPoints: currentPoints,
          intervalStrings:
              intervals, // These are values, labels are handled in UI
        );
      });
    }
  }

  String _formatDuration(int ms) {
    final duration = Duration(milliseconds: ms);
    final minutes = duration.inMinutes;
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    final milliseconds =
        (duration.inMilliseconds % 1000).toString().padLeft(3, '0');
    return "$minutes:$seconds.$milliseconds";
  }

  @override
  Widget build(BuildContext context) {
    final pilots = _stats.values.toList();
    // Sort: 0 is best
    // Sort: 1. Completed Laps (desc), 2. Best Lap Time (asc)
    pilots.sort((a, b) {
      // 1. Completed Laps (Descending)
      if (b.completedLaps != a.completedLaps) {
        return b.completedLaps.compareTo(a.completedLaps);
      }

      // 2. Best Lap Time (Ascending)
      if (a.bestLapTime == 0 && b.bestLapTime == 0) return 0;
      if (a.bestLapTime == 0) return 1; // Put 0 at bottom
      if (b.bestLapTime == 0) return -1;
      return a.bestLapTime.compareTo(b.bestLapTime);
    });

    return Container(
      width: 300,
      margin: const EdgeInsets.only(top: 100, left: 16, bottom: 32),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.white24)),
            ),
            child: const Text(
              "LEADERBOARD",
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: pilots.length,
              itemBuilder: (context, index) {
                final pilot = pilots[index];
                final isExpanded = _expandedPilotId == pilot.uid;

                return Column(
                  children: [
                    InkWell(
                      onTap: () {
                        setState(() {
                          _expandedPilotId = isExpanded ? null : pilot.uid;
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            vertical: 8, horizontal: 12),
                        color: index % 2 == 0
                            ? Colors.white.withOpacity(0.05)
                            : Colors.transparent,
                        child: Row(
                          children: [
                            Container(
                              width: 24,
                              alignment: Alignment.center,
                              child: Text(
                                "${index + 1}",
                                style: const TextStyle(
                                    color: Colors.white70,
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    pilot.displayName,
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    "Best: ${pilot.bestLapTime > 0 ? _formatDuration(pilot.bestLapTime.toInt()) : '-'}",
                                    style: const TextStyle(
                                        color: Colors.greenAccent,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12),
                                  ),
                                  Text(
                                    "Avg: ${pilot.averageLapTime > 0 ? _formatDuration(pilot.averageLapTime.toInt()) : '-'}",
                                    style: const TextStyle(
                                        color: Colors.white70, fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                            Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    "Lap ${pilot.currentLapNumber}",
                                    style: const TextStyle(
                                        color: Colors.white70, fontSize: 12),
                                  ),
                                ])
                          ],
                        ),
                      ),
                    ),
                    if (isExpanded)
                      Container(
                        color: Colors.black45,
                        padding: const EdgeInsets.all(8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "INTERVALS (CURRENT LAP)",
                              style: TextStyle(
                                  color: Colors.white54, fontSize: 10),
                            ),
                            const SizedBox(height: 4),
                            ...List.generate(pilot.intervalStrings.length, (i) {
                              return Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 2),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                        "Interval ${String.fromCharCode(65 + i)}-${String.fromCharCode(65 + i + 1)}",
                                        style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 12)),
                                    Text(pilot.intervalStrings[i],
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold)),
                                  ],
                                ),
                              );
                            }),
                            if (pilot.intervalStrings.isEmpty)
                              const Text("No intervals recorded",
                                  style: TextStyle(
                                      color: Colors.white30, fontSize: 12))
                          ],
                        ),
                      )
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
