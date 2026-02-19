import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:speed_data/features/models/competitor_model.dart';
import 'package:speed_data/features/models/lap_analysis_model.dart';
import 'package:speed_data/features/models/passing_model.dart';
import 'package:speed_data/features/models/race_session_model.dart';
import 'package:speed_data/features/models/session_analysis_summary_model.dart';
import 'package:speed_data/features/services/firestore_service.dart';
import 'package:speed_data/theme/speed_data_theme.dart';

class LeaderboardPanel extends StatefulWidget {
  final String raceId;
  final String? eventId;
  final String? sessionId;
  final List<dynamic> checkpoints;
  final SessionType sessionType;
  final Map<String, Competitor> competitorsByUid;
  final RaceSession? session;
  final FirestoreService? firestoreService;
  final Stream<List<PassingModel>>? passingsStream;
  final Stream<Map<String, List<LapAnalysisModel>>>? sessionLapsStream;
  final Stream<SessionAnalysisSummaryModel?>? sessionSummaryStream;
  final bool disableParticipantsSubscription;

  const LeaderboardPanel({
    Key? key,
    required this.raceId,
    this.eventId,
    this.sessionId,
    required this.checkpoints,
    this.sessionType = SessionType.race,
    this.competitorsByUid = const {},
    this.session,
    this.firestoreService,
    this.passingsStream,
    this.sessionLapsStream,
    this.sessionSummaryStream,
    this.disableParticipantsSubscription = false,
  }) : super(key: key);

  @override
  State<LeaderboardPanel> createState() => _LeaderboardPanelState();
}

class PilotStats {
  final String uid;
  final String displayName;
  final String carNumber;
  final double averageLapTime; // in ms
  final double bestLapTime; // in ms
  final int bestLapNumber;
  final int completedLaps;
  final int currentLapNumber;
  final Map<String, dynamic> currentPoints;
  final double sessionDurationMs;
  final double lastLapTime;
  // Instead of passing strings, let's keep it simple or update the logic where it's generated.
  // The existing code passes `intervalStrings`. I'll update how they are generated.
  final List<String> intervalStrings;

  PilotStats({
    required this.uid,
    required this.displayName,
    required this.carNumber,
    required this.averageLapTime,
    required this.bestLapTime,
    required this.bestLapNumber,
    required this.completedLaps,
    required this.currentLapNumber,
    required this.currentPoints,
    required this.sessionDurationMs,
    required this.lastLapTime,
    required this.intervalStrings,
  });
}

class _LeaderboardPanelState extends State<LeaderboardPanel> {
  FirestoreService? _localFirestoreService;
  StreamSubscription<QuerySnapshot>? _participantsSubscription;
  StreamSubscription<List<PassingModel>>? _passingsSubscription;
  StreamSubscription<Map<String, List<LapAnalysisModel>>>?
      _sessionLapsSubscription;
  StreamSubscription<SessionAnalysisSummaryModel?>? _sessionSummarySubscription;
  final ScrollController _verticalScrollController = ScrollController();
  final ScrollController _horizontalScrollController = ScrollController();
  final Map<String, PilotStats> _stats = {};
  final Map<String, String> _pilotNames = {};
  final Map<String, String> _pilotNumbers = {};
  List<PassingModel> _latestPassings = const [];
  Map<String, List<LapAnalysisModel>> _sessionLapsByUid = const {};
  SessionAnalysisSummaryModel? _sessionSummary;
  static const double _posColWidth = 48;
  static const double _numColWidth = 48;
  static const double _nameColWidth = 220;
  static const double _lapsColWidth = 56;
  static const double _metricColWidth = 120;
  static const double _rowPaddingHorizontal = 8;

  @override
  void initState() {
    super.initState();
    _updatePilotRosterFromWidget();
    _subscribeParticipants();
    _subscribeSessionAnalytics();
    _subscribePassings();
  }

  FirestoreService get _firestoreService =>
      widget.firestoreService ??
      (_localFirestoreService ??= FirestoreService());

  @override
  void didUpdateWidget(LeaderboardPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final sessionChanged = oldWidget.sessionId != widget.sessionId;
    final eventChanged = oldWidget.eventId != widget.eventId;
    final streamsChanged = oldWidget.passingsStream != widget.passingsStream ||
        oldWidget.sessionLapsStream != widget.sessionLapsStream ||
        oldWidget.sessionSummaryStream != widget.sessionSummaryStream ||
        oldWidget.disableParticipantsSubscription !=
            widget.disableParticipantsSubscription;
    final competitorsChanged =
        !mapEquals(oldWidget.competitorsByUid, widget.competitorsByUid);
    if (sessionChanged ||
        eventChanged ||
        competitorsChanged ||
        streamsChanged) {
      _resetSubscriptions();
      _updatePilotRosterFromWidget();
      _subscribeParticipants();
      _subscribeSessionAnalytics();
      _subscribePassings();
    }
  }

  @override
  void dispose() {
    _resetSubscriptions();
    _verticalScrollController.dispose();
    _horizontalScrollController.dispose();
    super.dispose();
  }

  void _subscribeParticipants() {
    if (widget.disableParticipantsSubscription) {
      _updatePilotRosterFromWidget();
      return;
    }

    _participantsSubscription?.cancel();
    _participantsSubscription = _firestoreService
        .getRaceLocations(
      widget.raceId,
      eventId: widget.eventId,
      sessionId: widget.sessionId,
    )
        .listen((snapshot) {
      bool hasChanges = false;
      for (var doc in snapshot.docs) {
        final uid = doc.id;
        final data = doc.data() as Map<String, dynamic>;
        final docName = (data['display_name'] as String?)?.trim();
        final docNumber = (data['car_number'] ?? data['number']) as String?;
        final competitor = widget.competitorsByUid[uid];
        final competitorName = competitor?.name;
        final competitorNumber = competitor?.number;

        final displayName =
            (competitorName != null && competitorName.isNotEmpty)
                ? competitorName
                : (docName != null && docName.isNotEmpty
                    ? docName
                    : _previewPilotName(uid));

        final carNumber =
            (competitorNumber != null && competitorNumber.isNotEmpty)
                ? competitorNumber
                : (docNumber != null && docNumber.isNotEmpty
                    ? docNumber
                    : _pilotNumbers[uid] ?? '??');

        if (_pilotNames[uid] != displayName ||
            _pilotNumbers[uid] != carNumber) {
          _pilotNames[uid] = displayName;
          _pilotNumbers[uid] = carNumber;
          hasChanges = true;
        }
      }
      if (hasChanges) setState(() {});
    });

    _updatePilotRosterFromWidget();
  }

  void _updatePilotRosterFromWidget() {
    bool updated = false;
    for (var entry in widget.competitorsByUid.entries) {
      final uid = entry.key;
      final name = entry.value.name.isNotEmpty
          ? entry.value.name
          : _previewPilotName(uid);
      final number = entry.value.number.isNotEmpty ? entry.value.number : '??';
      if (_pilotNames[uid] != name || _pilotNumbers[uid] != number) {
        _pilotNames[uid] = name;
        _pilotNumbers[uid] = number;
        updated = true;
      }
    }
    if (updated) setState(() {});
  }

  void _subscribePassings() {
    _passingsSubscription?.cancel();
    final passingsStream = widget.passingsStream ??
        _firestoreService.getPassingsStream(
          widget.raceId,
          sessionId: widget.sessionId,
          eventId: widget.eventId,
          session: widget.session,
        );
    _passingsSubscription = passingsStream.listen((passings) {
      _latestPassings = passings;
      _recomputeStats();
    });
    _recomputeStats();
  }

  void _subscribeSessionAnalytics() {
    _sessionLapsSubscription?.cancel();
    _sessionSummarySubscription?.cancel();
    _sessionLapsByUid = const {};
    _sessionSummary = null;

    final hasSession =
        widget.sessionId != null && widget.sessionId!.trim().isNotEmpty;
    final hasInjectedAnalytics =
        widget.sessionLapsStream != null || widget.sessionSummaryStream != null;
    if (!hasSession && !hasInjectedAnalytics) return;

    final lapsStream = widget.sessionLapsStream ??
        _firestoreService.getSessionParticipantsLapsModels(
          widget.raceId,
          eventId: widget.eventId,
          sessionId: widget.sessionId,
        );
    _sessionLapsSubscription = lapsStream.listen((lapsByUid) {
      _sessionLapsByUid = lapsByUid;
      _recomputeStats();
    });

    final summaryStream = widget.sessionSummaryStream ??
        _firestoreService.getSessionLeaderboardSummary(
          widget.raceId,
          eventId: widget.eventId,
          sessionId: widget.sessionId,
        );
    _sessionSummarySubscription = summaryStream.listen((summary) {
      _sessionSummary = summary;
      _recomputeStats();
    });
  }

  void _recomputeStats() {
    final hasSessionAnalytics = _sessionLapsByUid.values
        .any((laps) => laps.any((lap) => lap.totalLapTimeMs > 0));
    final newStats = hasSessionAnalytics
        ? _buildStatsFromSessionLaps(_sessionLapsByUid)
        : _buildStatsFromPassings(_latestPassings);

    void applyStats() {
      _stats
        ..clear()
        ..addAll(newStats);
    }

    if (!mounted) {
      applyStats();
      return;
    }

    setState(applyStats);
  }

  Map<String, PilotStats> _buildStatsFromPassings(List<PassingModel> passings) {
    final aggregates = <String, _PassingAggregate>{};

    for (final passing in passings) {
      final uid = passing.participantUid;
      if (uid.isEmpty || uid == 'SYSTEM') continue;
      if (_isPassingInvalid(passing)) continue;

      final aggregate = aggregates.putIfAbsent(uid, () => _PassingAggregate());
      final timestamp = passing.timestamp;
      if (aggregate.firstTimestamp == null ||
          timestamp.isBefore(aggregate.firstTimestamp!)) {
        aggregate.firstTimestamp = timestamp;
      }
      if (aggregate.lastTimestamp == null ||
          timestamp.isAfter(aggregate.lastTimestamp!)) {
        aggregate.lastTimestamp = timestamp;
        if (passing.lapTime != null) {
          aggregate.lastLapTime = passing.lapTime!;
          aggregate.lastLapNumber = passing.lapNumber;
        }
      }
      if (passing.lapTime != null && passing.lapTime! > 0) {
        aggregate.completedLaps =
            math.max(aggregate.completedLaps, passing.lapNumber);
        aggregate.validLapCount++;
        aggregate.totalLapTime += passing.lapTime!;
        if (passing.lapTime! < aggregate.bestLapTime) {
          aggregate.bestLapTime = passing.lapTime!;
          aggregate.bestLapNumber = passing.lapNumber;
        }
      }
    }

    final allParticipantIds = aggregates.entries
        .where((entry) => entry.value.validLapCount > 0)
        .map((entry) => entry.key)
        .toSet();

    final newStats = <String, PilotStats>{};
    for (final uid in allParticipantIds) {
      final aggregate = aggregates[uid];
      final bestLap = aggregate?.bestLapTime ?? double.infinity;
      final double average = (aggregate != null && aggregate.validLapCount > 0)
          ? aggregate.totalLapTime / aggregate.validLapCount
          : 0.0;
      final sessionDuration = (aggregate != null &&
              aggregate.firstTimestamp != null &&
              aggregate.lastTimestamp != null &&
              aggregate.lastTimestamp!.isAfter(aggregate.firstTimestamp!))
          ? aggregate.lastTimestamp!
              .difference(aggregate.firstTimestamp!)
              .inMilliseconds
              .toDouble()
          : 0.0;
      final lastLap = aggregate?.lastLapTime ?? 0.0;

      newStats[uid] = PilotStats(
        uid: uid,
        displayName: _pilotNames[uid] ??
            widget.competitorsByUid[uid]?.name ??
            _previewPilotName(uid),
        carNumber:
            _pilotNumbers[uid] ?? widget.competitorsByUid[uid]?.number ?? '??',
        averageLapTime: average,
        bestLapTime: bestLap == double.infinity ? 0 : bestLap,
        bestLapNumber: aggregate?.bestLapNumber ?? 0,
        completedLaps: aggregate?.completedLaps ?? 0,
        currentLapNumber: aggregate?.completedLaps ?? 0,
        currentPoints: const {},
        sessionDurationMs: sessionDuration,
        lastLapTime: lastLap,
        intervalStrings: const [],
      );
    }

    return newStats;
  }

  Map<String, PilotStats> _buildStatsFromSessionLaps(
      Map<String, List<LapAnalysisModel>> lapsByUid) {
    final newStats = <String, PilotStats>{};

    for (final entry in lapsByUid.entries) {
      final uid = entry.key;
      final allLaps = List<LapAnalysisModel>.from(entry.value)
        ..sort((a, b) => a.number.compareTo(b.number));
      if (allLaps.isEmpty) continue;

      final validLaps =
          allLaps.where(_isValidLapTimeForSummary).toList(growable: false);
      if (validLaps.isEmpty) continue;

      LapAnalysisModel bestLapModel = validLaps.first;
      for (final lap in validLaps) {
        if (lap.totalLapTimeMs < bestLapModel.totalLapTimeMs) {
          bestLapModel = lap;
        }
      }

      final completedLaps = validLaps.length;
      final totalLapTime =
          validLaps.fold<int>(0, (acc, lap) => acc + lap.totalLapTimeMs);
      final averageLapTime =
          completedLaps > 0 ? totalLapTime / completedLaps : 0.0;
      final lastLap = allLaps.last.totalLapTimeMs > 0
          ? allLaps.last.totalLapTimeMs.toDouble()
          : validLaps.last.totalLapTimeMs.toDouble();
      final currentLap = allLaps.last.number;

      int? firstStartMs;
      int? lastEndMs;
      for (final lap in allLaps) {
        if (lap.lapStartMs > 0) {
          if (firstStartMs == null || lap.lapStartMs < firstStartMs) {
            firstStartMs = lap.lapStartMs;
          }
        }
        if (lap.lapEndMs > 0) {
          if (lastEndMs == null || lap.lapEndMs > lastEndMs) {
            lastEndMs = lap.lapEndMs;
          }
        }
      }
      final sessionDurationMs = (firstStartMs != null &&
              lastEndMs != null &&
              lastEndMs > firstStartMs)
          ? (lastEndMs - firstStartMs).toDouble()
          : 0.0;

      newStats[uid] = PilotStats(
        uid: uid,
        displayName: _pilotNames[uid] ??
            widget.competitorsByUid[uid]?.name ??
            _previewPilotName(uid),
        carNumber:
            _pilotNumbers[uid] ?? widget.competitorsByUid[uid]?.number ?? '??',
        averageLapTime: averageLapTime,
        bestLapTime: bestLapModel.totalLapTimeMs.toDouble(),
        bestLapNumber: bestLapModel.number,
        completedLaps: completedLaps,
        currentLapNumber: currentLap,
        currentPoints: const {},
        sessionDurationMs: sessionDurationMs,
        lastLapTime: lastLap,
        intervalStrings: const [],
      );
    }

    return newStats;
  }

  bool _isPassingInvalid(PassingModel passing) {
    final flags = passing.flags.map((flag) => flag.toLowerCase()).toSet();
    if (flags.contains('invalid') || flags.contains('deleted')) {
      return true;
    }

    final minLapTimeSeconds = widget.session?.minLapTimeSeconds ?? 0;
    if (minLapTimeSeconds > 0 && passing.lapTime != null) {
      final minLapMs = minLapTimeSeconds * 1000;
      if (passing.lapTime! < minLapMs) {
        return true;
      }
    }

    return false;
  }

  void _resetSubscriptions() {
    _participantsSubscription?.cancel();
    _participantsSubscription = null;
    _passingsSubscription?.cancel();
    _passingsSubscription = null;
    _sessionLapsSubscription?.cancel();
    _sessionLapsSubscription = null;
    _sessionSummarySubscription?.cancel();
    _sessionSummarySubscription = null;
    _latestPassings = const [];
    _sessionLapsByUid = const {};
    _sessionSummary = null;
    _stats.clear();
  }

  String _formatDuration(int ms) {
    final duration = Duration(milliseconds: ms);
    final minutes = duration.inMinutes;
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    final milliseconds =
        (duration.inMilliseconds % 1000).toString().padLeft(3, '0');
    return "$minutes:$seconds.$milliseconds";
  }

  String _formatOptionalDuration(int? ms) {
    if (ms == null || ms <= 0) return '-';
    return _formatDuration(ms);
  }

  bool _isValidLapTimeForSummary(LapAnalysisModel lap) {
    if (!lap.valid || lap.totalLapTimeMs <= 0) {
      return false;
    }
    final minLapTimeSeconds = widget.session?.minLapTimeSeconds ?? 0;
    if (minLapTimeSeconds <= 0) {
      return true;
    }
    return lap.totalLapTimeMs >= (minLapTimeSeconds * 1000);
  }

  _DerivedSessionSummary _deriveSummaryFromSessionLaps() {
    int? bestLapMs;
    final Map<int, int> bestSectorByIndex = {};

    for (final laps in _sessionLapsByUid.values) {
      for (final lap in laps) {
        if (!_isValidLapTimeForSummary(lap)) continue;

        if (bestLapMs == null || lap.totalLapTimeMs < bestLapMs) {
          bestLapMs = lap.totalLapTimeMs;
        }

        for (int i = 0; i < lap.sectorsMs.length; i++) {
          final sectorMs = lap.sectorsMs[i];
          if (sectorMs <= 0) continue;
          final sectorIndex = i + 1;
          final currentBest = bestSectorByIndex[sectorIndex];
          if (currentBest == null || sectorMs < currentBest) {
            bestSectorByIndex[sectorIndex] = sectorMs;
          }
        }
      }
    }

    int? optimalLapMs;
    if (bestSectorByIndex.isNotEmpty) {
      final sortedIndexes = bestSectorByIndex.keys.toList()..sort();
      optimalLapMs = sortedIndexes.fold<int>(
          0, (acc, idx) => acc + bestSectorByIndex[idx]!);
    }

    return _DerivedSessionSummary(
      bestLapMs: bestLapMs,
      optimalLapMs: optimalLapMs,
    );
  }

  String _previewPilotName(String uid) {
    if (uid.isEmpty) return 'Pilot';
    final previewId = uid.length >= 4 ? uid.substring(0, 4) : uid;
    return 'Pilot $previewId';
  }

  @override
  Widget build(BuildContext context) {
    final pilots = _stats.values.toList();
    // Sort: 0 is best
    // Sort: 1. Completed Laps (desc), 2. Best Lap Time (asc)
    pilots.sort((a, b) {
      if (widget.sessionType == SessionType.qualifying ||
          widget.sessionType == SessionType.practice) {
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

    final derivedSummary = _deriveSummaryFromSessionLaps();
    final summaryBestLapMs =
        (_sessionSummary?.bestLapMs != null && _sessionSummary!.bestLapMs! > 0)
            ? _sessionSummary!.bestLapMs
            : null;
    final summaryOptimalLapMs = (_sessionSummary?.optimalLapMs != null &&
            _sessionSummary!.optimalLapMs! > 0)
        ? _sessionSummary!.optimalLapMs
        : null;
    // Prefer derived values from explicitly valid laps; use backend summary as fallback.
    final effectiveBestLapMs = derivedSummary.bestLapMs ?? summaryBestLapMs;
    final effectiveOptimalLapMs =
        derivedSummary.optimalLapMs ?? summaryOptimalLapMs;

    // Prefer analytical summary baseline when present (best_lap_ms / optimal_lap_ms).
    final summaryReferenceBestLapMs =
        (effectiveBestLapMs != null && effectiveBestLapMs > 0)
            ? effectiveBestLapMs.toDouble()
            : (pilots.isNotEmpty ? pilots.first.bestLapTime : 0.0);

    final tableWidth = (_rowPaddingHorizontal * 2) +
        _posColWidth +
        _numColWidth +
        _nameColWidth +
        _lapsColWidth +
        (_metricColWidth * 5);

    return Scrollbar(
      controller: _horizontalScrollController,
      thumbVisibility: true,
      notificationPredicate: (notification) =>
          notification.metrics.axis == Axis.horizontal,
      child: SingleChildScrollView(
        controller: _horizontalScrollController,
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: tableWidth,
          child: Column(
            children: [
              if (effectiveBestLapMs != null || effectiveOptimalLapMs != null)
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  color: SpeedDataTheme.bgBase,
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    children: [
                      const Text(
                        'SESSION SUMMARY',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: SpeedDataTheme.textSecondary,
                        ),
                      ),
                      Text(
                        'best_lap: ${_formatOptionalDuration(effectiveBestLapMs)}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontFamily: 'monospace',
                          color: SpeedDataTheme.dataSpeed,
                        ),
                      ),
                      Text(
                        'optimal_lap: ${_formatOptionalDuration(effectiveOptimalLapMs)}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontFamily: 'monospace',
                          color: SpeedDataTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              // Header
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                color: SpeedDataTheme.bgElevated,
                child: Row(
                  children: const [
                    SizedBox(
                        width: _posColWidth,
                        child: Text('POS',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 12))),
                    SizedBox(
                        width: _numColWidth,
                        child: Text('#',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 12))),
                    SizedBox(
                        width: _nameColWidth,
                        child: Text('NAME',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 12))),
                    SizedBox(
                        width: _lapsColWidth,
                        child: Text('LAPS',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 12))),
                    SizedBox(
                        width: _metricColWidth,
                        child: Text('TOTAL',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 12))),
                    SizedBox(
                        width: _metricColWidth,
                        child: Text('DIFF',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 12))),
                    SizedBox(
                        width: _metricColWidth,
                        child: Text('GAP',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 12))),
                    SizedBox(
                        width: _metricColWidth,
                        child: Text('BEST',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 12))),
                    SizedBox(
                        width: _metricColWidth,
                        child: Text('LAST',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 12))),
                  ],
                ),
              ),
              const Divider(height: 1, color: SpeedDataTheme.borderColor),
              Expanded(
                child: Scrollbar(
                  controller: _verticalScrollController,
                  thumbVisibility: true,
                  child: ListView.separated(
                    controller: _verticalScrollController,
                    itemCount: pilots.length,
                    separatorBuilder: (context, index) => const Divider(
                        height: 1, color: SpeedDataTheme.borderSubtle),
                    itemBuilder: (context, index) {
                      final stat = pilots[index];
                      final pos = index + 1;

                      // Diff & Gap Calculations
                      String diffStr = '-';
                      String gapStr = '-';

                      if (index > 0) {
                        final leader = pilots[0];
                        final prev = pilots[index - 1];

                        if (widget.sessionType == SessionType.race) {
                          // Race: Diff in laps or time
                          if (leader.completedLaps > stat.completedLaps) {
                            final lapDiff =
                                leader.completedLaps - stat.completedLaps;
                            diffStr = '-$lapDiff Laps';
                          } else {
                            // Same lap, diff in total time (if available) - for now using best lap diff as proxy or placeholder
                            diffStr = (stat.bestLapTime > 0 &&
                                    leader.bestLapTime > 0)
                                ? '+${((stat.bestLapTime - leader.bestLapTime) / 1000).toStringAsFixed(3)}'
                                : '-';
                          }

                          if (prev.completedLaps > stat.completedLaps) {
                            final lapGap =
                                prev.completedLaps - stat.completedLaps;
                            gapStr = '-$lapGap Laps';
                          } else {
                            gapStr = (stat.bestLapTime > 0 &&
                                    prev.bestLapTime > 0)
                                ? '+${((stat.bestLapTime - prev.bestLapTime) / 1000).toStringAsFixed(3)}'
                                : '-';
                          }
                        } else {
                          // Practice/Qualifying: Diff in Best Lap Time
                          if (stat.bestLapTime > 0 &&
                              summaryReferenceBestLapMs > 0) {
                            diffStr =
                                '+${((stat.bestLapTime - summaryReferenceBestLapMs) / 1000).toStringAsFixed(3)}';
                          }
                          if (stat.bestLapTime > 0 && prev.bestLapTime > 0) {
                            gapStr =
                                '+${((stat.bestLapTime - prev.bestLapTime) / 1000).toStringAsFixed(3)}';
                          }
                        }
                      }

                      final totalTime = stat.sessionDurationMs > 0
                          ? _formatDuration(stat.sessionDurationMs.round())
                          : '-';
                      final bestLap = stat.bestLapTime > 0
                          ? '${_formatDuration(stat.bestLapTime.round())}${stat.bestLapNumber > 0 ? ' (L${stat.bestLapNumber})' : ''}'
                          : '-';
                      final lastLap = stat.lastLapTime > 0
                          ? _formatDuration(stat.lastLapTime.round())
                          : '-';

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
                              const PopupMenuItem(
                                  value: 'dns', child: Text('Set DNS')),
                              const PopupMenuItem(
                                  value: 'dnf', child: Text('Set DNF')),
                              const PopupMenuItem(
                                  value: 'dq', child: Text('Set DQ')),
                              const PopupMenuItem(
                                  value: 'garage',
                                  child: Text('Send to Garage')),
                              const PopupMenuItem(
                                  value: 'penalty',
                                  child: Text('Apply Penalty...')),
                            ],
                          ).then((value) {
                            if (value != null) {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                  content: Text(
                                      'Action $value selected for ${stat.displayName}')));
                            }
                          });
                        },
                        child: Container(
                          color: index % 2 == 0
                              ? SpeedDataTheme.bgSurface
                              : SpeedDataTheme.bgBase, // Striped rows
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          child: Row(
                            children: [
                              SizedBox(
                                  width: _posColWidth,
                                  child: Text('$pos',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12))),
                              SizedBox(
                                  width: _numColWidth,
                                  child: Text(stat.carNumber,
                                      style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color:
                                              SpeedDataTheme.textSecondary))),
                              SizedBox(
                                  width: _nameColWidth,
                                  child: Text(stat.displayName,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500))),
                              SizedBox(
                                  width: _lapsColWidth,
                                  child: Text('${stat.completedLaps}',
                                      style: const TextStyle(fontSize: 12))),
                              SizedBox(
                                  width: _metricColWidth,
                                  child: Text(totalTime,
                                      style: const TextStyle(
                                          fontSize: 12,
                                          fontFamily: 'monospace'))),
                              SizedBox(
                                  width: _metricColWidth,
                                  child: Text(diffStr,
                                      style: const TextStyle(
                                          fontSize: 12,
                                          fontFamily: 'monospace',
                                          color:
                                              SpeedDataTheme.textSecondary))),
                              SizedBox(
                                  width: _metricColWidth,
                                  child: Text(gapStr,
                                      style: const TextStyle(
                                          fontSize: 12,
                                          fontFamily: 'monospace',
                                          color:
                                              SpeedDataTheme.textSecondary))),
                              SizedBox(
                                  width: _metricColWidth,
                                  child: Text(bestLap,
                                      style: const TextStyle(
                                          fontSize: 12,
                                          fontFamily: 'monospace',
                                          color: SpeedDataTheme.dataSpeed))),
                              SizedBox(
                                  width: _metricColWidth,
                                  child: Text(lastLap,
                                      style: const TextStyle(
                                          fontSize: 12,
                                          fontFamily: 'monospace'))),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PassingAggregate {
  int completedLaps = 0;
  double totalLapTime = 0;
  int validLapCount = 0;
  double bestLapTime = double.infinity;
  int bestLapNumber = 0;
  double lastLapTime = 0;
  int lastLapNumber = 0;
  DateTime? firstTimestamp;
  DateTime? lastTimestamp;
}

class _DerivedSessionSummary {
  final int? bestLapMs;
  final int? optimalLapMs;

  const _DerivedSessionSummary({
    required this.bestLapMs,
    required this.optimalLapMs,
  });
}
