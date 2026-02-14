import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:speed_data/features/services/firestore_service.dart';
import 'package:speed_data/features/models/race_session_model.dart';
import 'package:speed_data/theme/speed_data_theme.dart';
import 'dart:async';

class LeaderboardPanel extends StatefulWidget {
  final String raceId;
  final List<dynamic> checkpoints;
  final SessionType sessionType;

  const LeaderboardPanel({
    Key? key,
    required this.raceId,
    required this.checkpoints,
    this.sessionType = SessionType.race,
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
      if (widget.sessionType == SessionType.qualifying || widget.sessionType == SessionType.practice) {
          // Sort by Best Lap Time (Ascending)
          if (a.bestLapTime == 0 && b.bestLapTime == 0) return 0;
          if (a.bestLapTime == 0) return 1; 
          if (b.bestLapTime == 0) return -1;
          return a.bestLapTime.compareTo(b.bestLapTime);
      } else {
        // Race: 1. Completed Laps (Descending)
        if (b.completedLaps != a.completedLaps) {
          return b.completedLaps.compareTo(a.completedLaps);
        }
        // 2. Best Lap Time (Ascending) - fallback if laps are equal
        if (a.bestLapTime == 0 && b.bestLapTime == 0) return 0;
        if (a.bestLapTime == 0) return 1; 
        if (b.bestLapTime == 0) return -1;
        return a.bestLapTime.compareTo(b.bestLapTime);
      }
    });

    return Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          color: SpeedDataTheme.bgElevated,
          child: Row(
            children: const [
              SizedBox(width: 40, child: Text('POS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
              SizedBox(width: 40, child: Text('#', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
              Expanded(flex: 3, child: Text('NAME', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
              SizedBox(width: 40, child: Text('LAPS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
              Expanded(flex: 2, child: Text('TOTAL', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
              Expanded(flex: 2, child: Text('DIFF', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
              Expanded(flex: 2, child: Text('GAP', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
              Expanded(flex: 2, child: Text('BEST', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
              Expanded(flex: 2, child: Text('LAST', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
            ],
          ),
        ),
        const Divider(height: 1, color: SpeedDataTheme.borderColor),
        Expanded(
          child: ListView.separated(
            itemCount: pilots.length,
            separatorBuilder: (context, index) => const Divider(height: 1, color: SpeedDataTheme.borderSubtle),
            itemBuilder: (context, index) {
              final stat = pilots[index];
              final pos = index + 1;
              final diff = index == 0 ? '-' : '+12.345'; // TODO: Calculate actual Diff
              final gap = index == 0 ? '-' : '+0.567'; // TODO: Calculate actual Gap
              final totalTime = '15:23.456'; // TODO: Calculate total time
              final bestLap = stat.bestLapTime > 0 ? (stat.bestLapTime / 1000).toStringAsFixed(3) : '-';
              final lastLap = stat.intervalStrings.isNotEmpty ? stat.intervalStrings.last : '-';

              return GestureDetector(
                onSecondaryTapDown: (details) {
                  showMenu(
                    context: context,
                    position: RelativeRect.fromLTRB(
                      details.globalPosition.dx,
                      details.globalPosition.dy,
                      details.globalPosition.dx,
                      details.globalPosition.dy,
                    ),
                    items: [
                      const PopupMenuItem(value: 'dns', child: Text('Set DNS')),
                      const PopupMenuItem(value: 'dnf', child: Text('Set DNF')),
                      const PopupMenuItem(value: 'dq', child: Text('Set DQ')),
                      const PopupMenuItem(value: 'garage', child: Text('Send to Garage')),
                      const PopupMenuItem(value: 'penalty', child: Text('Apply Penalty...')),
                    ],
                  ).then((value) {
                    if (value != null) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Action $value selected for ${stat.displayName}')));
                    }
                  });
                },
                child: Container(
                  color: index % 2 == 0 ? SpeedDataTheme.bgSurface : SpeedDataTheme.bgBase, // Striped rows
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    children: [
                      SizedBox(width: 40, child: Text('$pos', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                      SizedBox(width: 40, child: Text('?', style: const TextStyle(fontSize: 12, color: SpeedDataTheme.textSecondary))), // Car Number
                      Expanded(flex: 3, child: Text(stat.displayName, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500))),
                      SizedBox(width: 40, child: Text('${stat.completedLaps}', style: const TextStyle(fontSize: 12))),
                      Expanded(flex: 2, child: Text(totalTime, style: const TextStyle(fontSize: 12, fontFamily: 'monospace'))),
                      Expanded(flex: 2, child: Text(diff, style: const TextStyle(fontSize: 12, fontFamily: 'monospace', color: SpeedDataTheme.textSecondary))),
                      Expanded(flex: 2, child: Text(gap, style: const TextStyle(fontSize: 12, fontFamily: 'monospace', color: SpeedDataTheme.textSecondary))),
                      Expanded(flex: 2, child: Text(bestLap, style: const TextStyle(fontSize: 12, fontFamily: 'monospace', color: SpeedDataTheme.dataSpeed))),
                      Expanded(flex: 2, child: Text(lastLap, style: const TextStyle(fontSize: 12, fontFamily: 'monospace'))),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
