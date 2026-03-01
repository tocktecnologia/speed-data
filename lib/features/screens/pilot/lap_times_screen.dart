import 'package:flutter/material.dart';
import 'package:speed_data/features/models/crossing_model.dart';
import 'package:speed_data/features/models/lap_analysis_model.dart';
import 'package:speed_data/features/models/passing_model.dart';
import 'package:speed_data/features/models/session_analysis_summary_model.dart';
import 'package:speed_data/features/screens/pilot/widgets/lap_times_details_map.dart';
import 'package:speed_data/features/screens/pilot/widgets/lap_times_formatters.dart';
import 'package:speed_data/features/screens/pilot/widgets/lap_times_graph_view.dart';
import 'package:speed_data/features/screens/pilot/widgets/lap_times_high_low_table.dart';
import 'package:speed_data/features/screens/pilot/widgets/lap_times_information_panel.dart';
import 'package:speed_data/features/screens/pilot/widgets/lap_times_splits_table.dart';
import 'package:speed_data/features/screens/pilot/widgets/lap_times_table.dart';
import 'package:speed_data/features/screens/pilot/widgets/lap_times_trap_speeds_table.dart';
import 'package:speed_data/features/screens/pilot/widgets/lap_times_types.dart';
import 'package:speed_data/features/services/firestore_service.dart';

class LapTimesScreen extends StatefulWidget {
  final String raceId;
  final String userId;
  final String raceName;
  final String? eventId;
  final String? initialSessionId;
  final String? fixedSessionLabel;
  final bool lockSessionSelection;

  // Optional overrides for tests and isolated rendering.
  final Stream<List<String>>? sessionIdsStreamOverride;
  final Stream<List<LapAnalysisModel>> Function(String? sessionId)?
      lapsStreamBuilder;
  final Stream<List<CrossingModel>> Function(String sessionId)?
      crossingsStreamBuilder;
  final Stream<SessionAnalysisSummaryModel?> Function(String sessionId)?
      summaryStreamBuilder;
  final LapTimesMode initialMode;

  const LapTimesScreen({
    super.key,
    required this.raceId,
    required this.userId,
    required this.raceName,
    this.eventId,
    this.initialSessionId,
    this.fixedSessionLabel,
    this.lockSessionSelection = false,
    this.sessionIdsStreamOverride,
    this.lapsStreamBuilder,
    this.crossingsStreamBuilder,
    this.summaryStreamBuilder,
    this.initialMode = LapTimesMode.sectors,
  });

  @override
  State<LapTimesScreen> createState() => _LapTimesScreenState();
}

class _LapTimesScreenState extends State<LapTimesScreen> {
  FirestoreService? _localFirestore;
  String? _selectedSessionId;
  bool _didInitializeSessionSelection = false;
  late LapTimesMode _selectedMode;
  LapTimesResultMode _resultMode = LapTimesResultMode.absolute;
  bool _hideInvalid = false;
  bool _showDetailsMap = false;
  bool _showGraphView = false;
  String? _comparisonLapId;
  String? _selectedLapId;
  bool _savingLapValidity = false;
  bool _mobileFiltersExpanded = false;

  FirestoreService get _firestore => _localFirestore ??= FirestoreService();
  bool get _allowLegacySessionSelection =>
      (widget.eventId == null || widget.eventId!.trim().isEmpty);
  bool get _isSessionSelectionLocked =>
      widget.lockSessionSelection &&
      (widget.initialSessionId?.trim().isNotEmpty ?? false);
  bool _isCompactLayout(BuildContext context) =>
      MediaQuery.sizeOf(context).width < 700;

  @override
  void initState() {
    super.initState();
    _selectedMode = widget.initialMode;
    final preferredSession = widget.initialSessionId?.trim();
    if (preferredSession != null && preferredSession.isNotEmpty) {
      _selectedSessionId = preferredSession;
    }
  }

  Stream<List<String>> _sessionIdsStream() {
    if (widget.sessionIdsStreamOverride != null) {
      return widget.sessionIdsStreamOverride!;
    }
    return _firestore
        .getPilotSessions(widget.raceId, widget.userId, eventId: widget.eventId)
        .map((snapshot) {
      final ids = snapshot.docs
          .map((doc) => doc.id.trim())
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();
      ids.sort();
      return ids;
    });
  }

  Stream<List<LapAnalysisModel>> _lapsStream(String? sessionId) {
    if (widget.lapsStreamBuilder != null) {
      return widget.lapsStreamBuilder!(sessionId);
    }
    if (!_allowLegacySessionSelection &&
        (sessionId == null || sessionId.isEmpty)) {
      return Stream<List<LapAnalysisModel>>.value(const <LapAnalysisModel>[]);
    }
    return _firestore.getLapsModels(
      widget.raceId,
      widget.userId,
      sessionId: sessionId,
      eventId: widget.eventId,
    );
  }

  Stream<List<CrossingModel>> _crossingsStream(String? sessionId) {
    if (sessionId == null || sessionId.isEmpty) {
      return Stream<List<CrossingModel>>.value(const []);
    }
    if (widget.crossingsStreamBuilder != null) {
      return widget.crossingsStreamBuilder!(sessionId);
    }
    return _firestore.getSessionCrossings(
      widget.raceId,
      widget.userId,
      sessionId,
      eventId: widget.eventId,
    );
  }

  Stream<SessionAnalysisSummaryModel?> _summaryStream(String? sessionId) {
    if (sessionId == null || sessionId.isEmpty) {
      return Stream<SessionAnalysisSummaryModel?>.value(null);
    }
    if (widget.summaryStreamBuilder != null) {
      return widget.summaryStreamBuilder!(sessionId);
    }
    return _firestore.getSessionAnalysisSummary(
      widget.raceId,
      widget.userId,
      sessionId,
      eventId: widget.eventId,
    );
  }

  Stream<List<PassingModel>> _passingsStream(String? sessionId) {
    if (sessionId == null || sessionId.isEmpty) {
      return Stream<List<PassingModel>>.value(const <PassingModel>[]);
    }
    return _firestore.getPassingsStream(
      widget.raceId,
      sessionId: sessionId,
      eventId: widget.eventId,
    );
  }

  bool _intListEquals(List<int> left, List<int> right) {
    if (identical(left, right)) return true;
    if (left.length != right.length) return false;
    for (int i = 0; i < left.length; i++) {
      if (left[i] != right[i]) return false;
    }
    return true;
  }

  List<int> _deriveSplitsFromCrossings(List<CrossingModel> lapCrossings) {
    final latestByCheckpoint = <int, CrossingModel>{};
    for (final crossing in lapCrossings) {
      final split = crossing.splitTimeMs;
      if (split == null || split < 0) continue;
      final current = latestByCheckpoint[crossing.checkpointIndex];
      if (current == null || crossing.crossedAtMs > current.crossedAtMs) {
        latestByCheckpoint[crossing.checkpointIndex] = crossing;
      }
    }
    final checkpointIndexes = latestByCheckpoint.keys.toList(growable: false)
      ..sort();
    return checkpointIndexes
        .map((index) => latestByCheckpoint[index]!.splitTimeMs!)
        .toList(growable: false);
  }

  List<int> _deriveSectorsFromCrossings(List<CrossingModel> lapCrossings) {
    final latestByCheckpoint = <int, CrossingModel>{};
    for (final crossing in lapCrossings) {
      final sector = crossing.sectorTimeMs;
      if (crossing.checkpointIndex <= 0 || sector == null || sector <= 0) {
        continue;
      }
      final current = latestByCheckpoint[crossing.checkpointIndex];
      if (current == null || crossing.crossedAtMs > current.crossedAtMs) {
        latestByCheckpoint[crossing.checkpointIndex] = crossing;
      }
    }
    final checkpointIndexes = latestByCheckpoint.keys.toList(growable: false)
      ..sort();
    return checkpointIndexes
        .map((index) => latestByCheckpoint[index]!.sectorTimeMs!)
        .toList(growable: false);
  }

  List<int> _deriveSectorsFromSplits(List<int> splits) {
    if (splits.isEmpty) return const <int>[];
    final sanitized =
        splits.where((value) => value >= 0).toList(growable: false);
    if (sanitized.isEmpty) return const <int>[];

    final sectors = <int>[];
    int? previous;
    for (final split in sanitized) {
      if (previous == null) {
        previous = split;
        continue;
      }
      final delta = split - previous;
      if (delta > 0) {
        sectors.add(delta);
      }
      previous = split;
    }

    if (sectors.isEmpty) {
      final lastSplit = sanitized.last;
      if (lastSplit > 0) {
        sectors.add(lastSplit);
      }
    }
    return sectors;
  }

  List<LapAnalysisModel> _enrichLapsWithCrossings(
    List<LapAnalysisModel> laps,
    List<CrossingModel> crossings,
  ) {
    if (laps.isEmpty || crossings.isEmpty) return laps;

    final crossingsByLap = <int, List<CrossingModel>>{};
    for (final crossing in crossings) {
      if (crossing.lapNumber <= 0) continue;
      crossingsByLap
          .putIfAbsent(crossing.lapNumber, () => <CrossingModel>[])
          .add(crossing);
    }

    bool changed = false;
    final enriched = <LapAnalysisModel>[];
    for (final lap in laps) {
      final lapCrossings = crossingsByLap[lap.number];
      if (lapCrossings == null || lapCrossings.isEmpty) {
        enriched.add(lap);
        continue;
      }

      final derivedSplits = _deriveSplitsFromCrossings(lapCrossings);
      final derivedSectors = _deriveSectorsFromCrossings(lapCrossings);
      final nextSplits = lap.splitsMs.isNotEmpty ? lap.splitsMs : derivedSplits;
      final nextSectors = lap.sectorsMs.isNotEmpty
          ? lap.sectorsMs
          : (derivedSectors.isNotEmpty
              ? derivedSectors
              : _deriveSectorsFromSplits(nextSplits));
      if (_intListEquals(nextSplits, lap.splitsMs) &&
          _intListEquals(nextSectors, lap.sectorsMs)) {
        enriched.add(lap);
        continue;
      }

      changed = true;
      enriched.add(
        LapAnalysisModel(
          id: lap.id,
          number: lap.number,
          lapStartMs: lap.lapStartMs,
          lapEndMs: lap.lapEndMs,
          totalLapTimeMs: lap.totalLapTimeMs,
          valid: lap.valid,
          invalidReasons: lap.invalidReasons,
          splitsMs: List<int>.from(nextSplits, growable: false),
          sectorsMs: List<int>.from(nextSectors, growable: false),
          trapSpeedsMps: lap.trapSpeedsMps,
          speedStats: lap.speedStats,
          distanceM: lap.distanceM,
          createdAtMs: lap.createdAtMs,
        ),
      );
    }

    return changed ? enriched : laps;
  }

  List<int> _deriveSplitsFromPassings(List<PassingModel> lapPassings) {
    final latestByCheckpoint = <int, PassingModel>{};
    for (final passing in lapPassings) {
      final split = passing.splitTime;
      if (split == null || split < 0) continue;
      final current = latestByCheckpoint[passing.checkpointIndex];
      if (current == null || passing.timestamp.isAfter(current.timestamp)) {
        latestByCheckpoint[passing.checkpointIndex] = passing;
      }
    }
    final checkpointIndexes = latestByCheckpoint.keys.toList(growable: false)
      ..sort();
    return checkpointIndexes
        .map((index) => latestByCheckpoint[index]!.splitTime!.round())
        .toList(growable: false);
  }

  List<int> _deriveSectorsFromPassings(List<PassingModel> lapPassings) {
    final latestByCheckpoint = <int, PassingModel>{};
    for (final passing in lapPassings) {
      final sector = passing.sectorTime;
      if (passing.checkpointIndex <= 0 || sector == null || sector <= 0) {
        continue;
      }
      final current = latestByCheckpoint[passing.checkpointIndex];
      if (current == null || passing.timestamp.isAfter(current.timestamp)) {
        latestByCheckpoint[passing.checkpointIndex] = passing;
      }
    }
    final checkpointIndexes = latestByCheckpoint.keys.toList(growable: false)
      ..sort();
    return checkpointIndexes
        .map((index) => latestByCheckpoint[index]!.sectorTime!.round())
        .toList(growable: false);
  }

  List<LapAnalysisModel> _enrichLapsWithPassings(
    List<LapAnalysisModel> laps,
    List<PassingModel> passings,
  ) {
    if (laps.isEmpty || passings.isEmpty) return laps;

    final passingsByLap = <int, List<PassingModel>>{};
    for (final passing in passings) {
      if (passing.lapNumber <= 0) continue;
      passingsByLap
          .putIfAbsent(passing.lapNumber, () => <PassingModel>[])
          .add(passing);
    }

    bool changed = false;
    final enriched = <LapAnalysisModel>[];
    for (final lap in laps) {
      final lapPassings = passingsByLap[lap.number];
      if (lapPassings == null || lapPassings.isEmpty) {
        enriched.add(lap);
        continue;
      }

      final derivedSplits = _deriveSplitsFromPassings(lapPassings);
      final derivedSectors = _deriveSectorsFromPassings(lapPassings);
      final nextSplits = lap.splitsMs.isNotEmpty ? lap.splitsMs : derivedSplits;
      final nextSectors = lap.sectorsMs.isNotEmpty
          ? lap.sectorsMs
          : (derivedSectors.isNotEmpty
              ? derivedSectors
              : _deriveSectorsFromSplits(nextSplits));
      if (_intListEquals(nextSplits, lap.splitsMs) &&
          _intListEquals(nextSectors, lap.sectorsMs)) {
        enriched.add(lap);
        continue;
      }

      changed = true;
      enriched.add(
        LapAnalysisModel(
          id: lap.id,
          number: lap.number,
          lapStartMs: lap.lapStartMs,
          lapEndMs: lap.lapEndMs,
          totalLapTimeMs: lap.totalLapTimeMs,
          valid: lap.valid,
          invalidReasons: lap.invalidReasons,
          splitsMs: List<int>.from(nextSplits, growable: false),
          sectorsMs: List<int>.from(nextSectors, growable: false),
          trapSpeedsMps: lap.trapSpeedsMps,
          speedStats: lap.speedStats,
          distanceM: lap.distanceM,
          createdAtMs: lap.createdAtMs,
        ),
      );
    }

    return changed ? enriched : laps;
  }

  List<PassingModel> _selectBestMatchingPassingsForLaps(
    List<PassingModel> passings,
    List<LapAnalysisModel> laps,
  ) {
    if (passings.isEmpty) return const <PassingModel>[];

    final passingsByUid = <String, List<PassingModel>>{};
    for (final passing in passings) {
      final uid = passing.participantUid.trim();
      if (uid.isEmpty || uid == 'SYSTEM') continue;
      passingsByUid.putIfAbsent(uid, () => <PassingModel>[]).add(passing);
    }
    if (passingsByUid.isEmpty) return const <PassingModel>[];
    if (passingsByUid.length == 1) {
      return passingsByUid.values.first;
    }

    final lapByNumber = <int, LapAnalysisModel>{
      for (final lap in laps) lap.number: lap,
    };
    final preferredUid = widget.userId.trim();
    final sectorsCountByUid = <String, int>{};
    final matchedLapsByUid = <String, int>{};
    String? bestUid;
    double bestScore = double.negativeInfinity;
    for (final entry in passingsByUid.entries) {
      final uid = entry.key;
      final uidPassings = entry.value;
      final matchedLapNumbers = <int>{};
      int lapTimeMatches = 0;
      int sectorsWithData = 0;
      int splitsWithData = 0;
      for (final passing in uidPassings) {
        final lap = lapByNumber[passing.lapNumber];
        if (lap != null) {
          matchedLapNumbers.add(passing.lapNumber);
          final lapTime = passing.lapTime;
          if (lapTime != null && (lapTime - lap.totalLapTimeMs).abs() <= 2000) {
            lapTimeMatches += 1;
          }
        }
        if (passing.sectorTime != null && passing.sectorTime! > 0) {
          sectorsWithData += 1;
        }
        if (passing.splitTime != null && passing.splitTime! > 0) {
          splitsWithData += 1;
        }
      }
      sectorsCountByUid[uid] = sectorsWithData;
      matchedLapsByUid[uid] = matchedLapNumbers.length;

      final score = (lapTimeMatches * 8) +
          (matchedLapNumbers.length * 4) +
          (sectorsWithData * 1.5) +
          (splitsWithData * 0.5) +
          (uid == preferredUid ? 2 : 0);
      if (score > bestScore) {
        bestScore = score;
        bestUid = uid;
      }
    }

    if (bestUid == null) return const <PassingModel>[];
    final bestUidSectors = sectorsCountByUid[bestUid] ?? 0;
    if (bestUidSectors <= 0) {
      String? sectorRichUid;
      int sectorRichScore = -1;
      for (final uid in passingsByUid.keys) {
        final matched = matchedLapsByUid[uid] ?? 0;
        final sectors = sectorsCountByUid[uid] ?? 0;
        final score = (matched * 1000) + sectors;
        if (score > sectorRichScore) {
          sectorRichScore = score;
          sectorRichUid = uid;
        }
      }
      if (sectorRichUid != null) {
        return passingsByUid[sectorRichUid] ?? const <PassingModel>[];
      }
    }
    return passingsByUid[bestUid] ?? const <PassingModel>[];
  }

  bool _lapsHaveSectorData(List<LapAnalysisModel> laps) {
    for (final lap in laps) {
      if (lap.sectorsMs.isNotEmpty) return true;
    }
    return false;
  }

  void _syncInitialSessionSelection(List<String> sessionIds) {
    if (_didInitializeSessionSelection) return;
    _didInitializeSessionSelection = true;
    if (sessionIds.isEmpty) return;

    final preferredSessionId = _selectedSessionId;
    final nextSessionId = preferredSessionId != null &&
            preferredSessionId.isNotEmpty &&
            sessionIds.contains(preferredSessionId)
        ? preferredSessionId
        : sessionIds.first;
    if (nextSessionId == _selectedSessionId) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _selectedSessionId = nextSessionId;
      });
    });
  }

  void _clearMissingSession(List<String> sessionIds) {
    if (_isSessionSelectionLocked) return;
    if (_selectedSessionId == null) return;
    if (sessionIds.contains(_selectedSessionId)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _selectedSessionId =
            !_allowLegacySessionSelection && sessionIds.isNotEmpty
                ? sessionIds.first
                : null;
        _comparisonLapId = null;
        _selectedLapId = null;
      });
    });
  }

  void _syncLapSelection({
    required List<LapAnalysisModel> candidateLaps,
    required LapAnalysisModel? comparisonLap,
    required LapAnalysisModel? selectedLap,
  }) {
    String? nextComparisonId = _comparisonLapId;
    String? nextSelectedId = _selectedLapId;

    if (comparisonLap != null && _comparisonLapId != comparisonLap.id) {
      nextComparisonId = comparisonLap.id;
    }
    if (selectedLap != null && _selectedLapId != selectedLap.id) {
      nextSelectedId = selectedLap.id;
    }
    final validIds = candidateLaps.map((lap) => lap.id).toSet();
    if (nextComparisonId != null && !validIds.contains(nextComparisonId)) {
      nextComparisonId = comparisonLap?.id;
    }
    if (nextSelectedId != null && !validIds.contains(nextSelectedId)) {
      nextSelectedId = selectedLap?.id;
    }
    if (nextComparisonId == _comparisonLapId &&
        nextSelectedId == _selectedLapId) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _comparisonLapId = nextComparisonId;
        _selectedLapId = nextSelectedId;
      });
    });
  }

  Future<void> _toggleLapValidity(
    LapAnalysisModel lap, {
    required bool nextValid,
  }) async {
    final sessionId = _selectedSessionId;
    if (sessionId == null || sessionId.isEmpty) return;
    setState(() => _savingLapValidity = true);
    try {
      await _firestore.setSessionLapValidity(
        raceId: widget.raceId,
        uid: widget.userId,
        sessionId: sessionId,
        lapId: lap.id,
        valid: nextValid,
        eventId: widget.eventId,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            nextValid
                ? 'Lap ${lap.number} marked as valid.'
                : 'Lap ${lap.number} marked as invalid.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update lap validity: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _savingLapValidity = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final compact = _isCompactLayout(context);
    return Scaffold(
      appBar: AppBar(
        title: Text('Lap Times - ${widget.raceName}'),
        actions: [
          IconButton(
            tooltip: _showDetailsMap ? 'Hide details map' : 'Show details map',
            icon: Icon(_showDetailsMap ? Icons.map_outlined : Icons.map),
            onPressed: () => setState(() => _showDetailsMap = !_showDetailsMap),
          ),
          IconButton(
            tooltip: _showGraphView ? 'Hide graph' : 'Show graph',
            icon: Icon(
                _showGraphView ? Icons.show_chart_outlined : Icons.show_chart),
            onPressed: () => setState(() => _showGraphView = !_showGraphView),
          ),
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(() {}),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildSessionSelector(compact: compact),
          _buildModeSelector(compact: compact),
          if (_allowLegacySessionSelection && _selectedSessionId == null)
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 8 : 12,
                vertical: 4,
              ),
              child: Text(
                'Legacy mode selected. Session analytics (crossings/summary) may be unavailable.',
                style: compact ? Theme.of(context).textTheme.bodySmall : null,
              ),
            ),
          Expanded(child: _buildModeContent()),
        ],
      ),
    );
  }

  Widget _buildSessionSelector({required bool compact}) {
    if (_isSessionSelectionLocked) {
      final sessionLabel = (widget.fixedSessionLabel != null &&
              widget.fixedSessionLabel!.trim().isNotEmpty)
          ? widget.fixedSessionLabel!.trim()
          : (_selectedSessionId ?? '-');
      return Padding(
        padding: EdgeInsets.fromLTRB(
          compact ? 8 : 12,
          compact ? 8 : 12,
          compact ? 8 : 12,
          compact ? 4 : 8,
        ),
        child: Row(
          children: [
            Text(
              'Session',
              style: compact ? Theme.of(context).textTheme.bodySmall : null,
            ),
            SizedBox(width: compact ? 8 : 12),
            Expanded(
              child: Container(
                padding: EdgeInsets.symmetric(
                    horizontal: 12, vertical: compact ? 10 : 14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Theme.of(context).dividerColor),
                ),
                child: Text(
                  sessionLabel,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return StreamBuilder<List<String>>(
      stream: _sessionIdsStream(),
      builder: (context, snapshot) {
        final sessionIds = snapshot.data ?? const <String>[];
        _syncInitialSessionSelection(sessionIds);
        _clearMissingSession(sessionIds);

        if (!_allowLegacySessionSelection && sessionIds.isEmpty) {
          return Padding(
            padding: EdgeInsets.fromLTRB(
              compact ? 8 : 12,
              compact ? 8 : 12,
              compact ? 8 : 12,
              compact ? 4 : 8,
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'No sessions available for this event yet.',
                style: compact ? Theme.of(context).textTheme.bodySmall : null,
              ),
            ),
          );
        }

        final items = <DropdownMenuItem<String?>>[
          if (_allowLegacySessionSelection)
            const DropdownMenuItem<String?>(
              value: null,
              child: Text('Legacy (no session)'),
            ),
          ...sessionIds.map(
            (sessionId) => DropdownMenuItem<String?>(
              value: sessionId,
              child: Text('Session: $sessionId'),
            ),
          ),
        ];

        return Padding(
          padding: EdgeInsets.fromLTRB(
            compact ? 8 : 12,
            compact ? 8 : 12,
            compact ? 8 : 12,
            compact ? 4 : 8,
          ),
          child: Row(
            children: [
              Text(
                'Session',
                style: compact ? Theme.of(context).textTheme.bodySmall : null,
              ),
              SizedBox(width: compact ? 8 : 12),
              Expanded(
                child: DropdownButtonFormField<String?>(
                  initialValue: _selectedSessionId,
                  isDense: compact,
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  items: items,
                  onChanged: (value) => setState(() {
                    _selectedSessionId = value;
                    _comparisonLapId = null;
                    _selectedLapId = null;
                  }),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildModeSelector({required bool compact}) {
    return SizedBox(
      height: compact ? 40 : 48,
      child: ListView(
        padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 12),
        scrollDirection: Axis.horizontal,
        children: [
          for (final mode in LapTimesMode.values)
            Padding(
              padding: EdgeInsets.only(right: compact ? 6 : 8),
              child: ChoiceChip(
                label: Text(mode.label),
                selected: _selectedMode == mode,
                visualDensity:
                    compact ? VisualDensity.compact : VisualDensity.standard,
                onSelected: (_) => setState(() => _selectedMode = mode),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildModeContent() {
    if (!_allowLegacySessionSelection &&
        (_selectedSessionId == null || _selectedSessionId!.isEmpty)) {
      return const Center(
        child: Text('Select a valid session to view Lap Times.'),
      );
    }

    return StreamBuilder<List<LapAnalysisModel>>(
      stream: _lapsStream(_selectedSessionId),
      builder: (context, lapsSnapshot) {
        if (lapsSnapshot.connectionState == ConnectionState.waiting &&
            !lapsSnapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final allLaps = lapsSnapshot.data ?? const <LapAnalysisModel>[];
        final sortedLaps = List<LapAnalysisModel>.from(allLaps)
          ..sort((a, b) => b.number.compareTo(a.number));
        final candidateLaps = _hideInvalid
            ? sortedLaps.where((lap) => lap.valid).toList(growable: false)
            : sortedLaps;

        final comparisonLap =
            candidateLaps.cast<LapAnalysisModel?>().firstWhere(
                  (lap) => lap?.id == _comparisonLapId,
                  orElse: () => selectReferenceLap(candidateLaps),
                );
        final selectedLap = candidateLaps.cast<LapAnalysisModel?>().firstWhere(
              (lap) => lap?.id == _selectedLapId,
              orElse: () =>
                  candidateLaps.isNotEmpty ? candidateLaps.first : null,
            );
        _syncLapSelection(
          candidateLaps: candidateLaps,
          comparisonLap: comparisonLap,
          selectedLap: selectedLap,
        );

        return StreamBuilder<SessionAnalysisSummaryModel?>(
          stream: _summaryStream(_selectedSessionId),
          builder: (context, summarySnapshot) {
            final summary = summarySnapshot.data;
            return StreamBuilder<List<CrossingModel>>(
              stream: _crossingsStream(_selectedSessionId),
              builder: (context, crossingsSnapshot) {
                final crossings =
                    crossingsSnapshot.data ?? const <CrossingModel>[];
                return StreamBuilder<List<PassingModel>>(
                  stream: _passingsStream(_selectedSessionId),
                  builder: (context, passingsSnapshot) {
                    final passings =
                        passingsSnapshot.data ?? const <PassingModel>[];
                    final selectedPassings = _selectBestMatchingPassingsForLaps(
                      passings,
                      sortedLaps,
                    );
                    final withCrossings =
                        _enrichLapsWithCrossings(sortedLaps, crossings);
                    var allLaps = _enrichLapsWithPassings(
                        withCrossings, selectedPassings);
                    if (!_lapsHaveSectorData(allLaps) && passings.isNotEmpty) {
                      allLaps =
                          _enrichLapsWithPassings(withCrossings, passings);
                    }
                    final lapById = <String, LapAnalysisModel>{
                      for (final lap in allLaps) lap.id: lap,
                    };
                    final visibleLaps = candidateLaps
                        .map((lap) => lapById[lap.id] ?? lap)
                        .toList(growable: false);
                    final comparisonLapResolved = comparisonLap == null
                        ? null
                        : (lapById[comparisonLap.id] ?? comparisonLap);
                    final selectedLapResolved = selectedLap == null
                        ? null
                        : (lapById[selectedLap.id] ?? selectedLap);

                    return _buildAnalysisLayout(
                      allLaps: allLaps,
                      visibleLaps: visibleLaps,
                      selectedLap: selectedLapResolved,
                      comparisonLap: comparisonLapResolved,
                      summary: summary,
                      crossings: crossings,
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildAnalysisLayout({
    required List<LapAnalysisModel> allLaps,
    required List<LapAnalysisModel> visibleLaps,
    required LapAnalysisModel? selectedLap,
    required LapAnalysisModel? comparisonLap,
    required SessionAnalysisSummaryModel? summary,
    required List<CrossingModel> crossings,
  }) {
    final compact = _isCompactLayout(context);
    final optimalSectors = deriveOptimalSectors(allLaps, summary: summary);
    final optimalLapMs =
        optimalSectors.fold<int>(0, (sum, value) => sum + value);
    final bestLap = selectReferenceLap(allLaps);
    final effectiveSummaryBest = bestLap?.totalLapTimeMs ?? summary?.bestLapMs;

    return Column(
      children: [
        _buildOptimalHeader(
          compact: compact,
          bestLapMs: effectiveSummaryBest,
          optimalLapMs: optimalLapMs > 0 ? optimalLapMs : summary?.optimalLapMs,
          validLapsCount: allLaps.where((lap) => lap.valid).length,
          totalLapsCount: allLaps.length,
        ),
        _buildAnalysisToolbar(
          compact: compact,
          allLaps: allLaps,
          visibleLaps: visibleLaps,
          selectedLap: selectedLap,
          comparisonLap: comparisonLap,
        ),
        Expanded(
          child: _buildSelectedModeWidget(
            laps: visibleLaps,
            summary: summary,
            crossings: crossings,
            selectedLapId: selectedLap?.id,
            comparisonLap: comparisonLap,
          ),
        ),
        if (_showDetailsMap && selectedLap != null)
          SizedBox(
            height: 240,
            child: LapTimesDetailsMap(
              mode: _selectedMode,
              selectedLap: selectedLap,
              comparisonLap: comparisonLap,
              crossings: crossings,
            ),
          ),
        if (_showGraphView && selectedLap != null)
          SizedBox(
            height: 240,
            child: LapTimesGraphView(
              mode: _selectedMode,
              selectedLap: selectedLap,
              comparisonLap: comparisonLap,
              resultMode: _resultMode,
            ),
          ),
      ],
    );
  }

  Widget _buildOptimalHeader({
    required bool compact,
    required int? bestLapMs,
    required int? optimalLapMs,
    required int validLapsCount,
    required int totalLapsCount,
  }) {
    return Container(
      width: double.infinity,
      margin: EdgeInsets.fromLTRB(
        compact ? 8 : 12,
        compact ? 6 : 8,
        compact ? 8 : 12,
        compact ? 4 : 8,
      ),
      padding: EdgeInsets.all(compact ? 8 : 12),
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .primaryContainer
            .withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.35),
        ),
      ),
      child: Wrap(
        spacing: compact ? 10 : 18,
        runSpacing: compact ? 4 : 6,
        children: [
          Text(
            'Optimal Lap: ${formatDurationMs(optimalLapMs)}',
            style: compact ? Theme.of(context).textTheme.bodySmall : null,
          ),
          Text(
            'Best Lap: ${formatDurationMs(bestLapMs)}',
            style: compact ? Theme.of(context).textTheme.bodySmall : null,
          ),
          Text(
            'Valid/Total: $validLapsCount / $totalLapsCount',
            style: compact ? Theme.of(context).textTheme.bodySmall : null,
          ),
        ],
      ),
    );
  }

  Widget _buildAnalysisToolbar({
    required bool compact,
    required List<LapAnalysisModel> allLaps,
    required List<LapAnalysisModel> visibleLaps,
    required LapAnalysisModel? selectedLap,
    required LapAnalysisModel? comparisonLap,
  }) {
    final canToggleValidity = _selectedSessionId != null &&
        _selectedSessionId!.isNotEmpty &&
        selectedLap != null;
    final comparisonItems = visibleLaps
        .map(
          (lap) => DropdownMenuItem<String>(
            value: lap.id,
            child: Text(
              'L${lap.number}${lap.valid ? '' : ' (INV)'}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
        )
        .toList(growable: false);
    final selectedItems = visibleLaps
        .map(
          (lap) => DropdownMenuItem<String>(
            value: lap.id,
            child: Text(
              'L${lap.number}${lap.valid ? '' : ' (INV)'}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
        )
        .toList(growable: false);

    if (compact) {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(8, 0, 8, 6),
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).dividerColor),
          borderRadius: BorderRadius.circular(8),
        ),
        child: ExpansionTile(
          key: const PageStorageKey<String>('lap-times-mobile-filters'),
          dense: true,
          tilePadding: const EdgeInsets.symmetric(horizontal: 10),
          childrenPadding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
          initiallyExpanded: _mobileFiltersExpanded,
          onExpansionChanged: (expanded) =>
              setState(() => _mobileFiltersExpanded = expanded),
          title: Text(
            'Filters',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          subtitle: Text(
            'Showing ${visibleLaps.length} / ${allLaps.length} laps',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ChoiceChip(
                  label: Text(LapTimesResultMode.absolute.label),
                  selected: _resultMode == LapTimesResultMode.absolute,
                  visualDensity: VisualDensity.compact,
                  onSelected: (_) =>
                      setState(() => _resultMode = LapTimesResultMode.absolute),
                ),
                ChoiceChip(
                  label: Text(LapTimesResultMode.difference.label),
                  selected: _resultMode == LapTimesResultMode.difference,
                  visualDensity: VisualDensity.compact,
                  onSelected: (_) => setState(
                      () => _resultMode = LapTimesResultMode.difference),
                ),
                FilterChip(
                  label: const Text('Hide invalid'),
                  selected: _hideInvalid,
                  visualDensity: VisualDensity.compact,
                  onSelected: (value) => setState(() {
                    _hideInvalid = value;
                    _comparisonLapId = null;
                    _selectedLapId = null;
                  }),
                ),
              ],
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: comparisonLap?.id ??
                  (comparisonItems.isNotEmpty
                      ? comparisonItems.first.value
                      : null),
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Comparison Lap',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              items: comparisonItems,
              onChanged: (value) => setState(() => _comparisonLapId = value),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: selectedLap?.id ??
                  (selectedItems.isNotEmpty ? selectedItems.first.value : null),
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Selected Lap',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              items: selectedItems,
              onChanged: (value) => setState(() => _selectedLapId = value),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: !canToggleValidity || _savingLapValidity
                    ? null
                    : () => _toggleLapValidity(
                          selectedLap,
                          nextValid: !selectedLap.valid,
                        ),
                icon: Icon(
                  selectedLap != null && selectedLap.valid
                      ? Icons.block
                      : Icons.verified,
                ),
                label: Text(
                  selectedLap != null && selectedLap.valid
                      ? 'Mark Invalid'
                      : 'Mark Valid',
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Column(
        children: [
          Row(
            children: [
              const Text('Result'),
              const SizedBox(width: 8),
              ChoiceChip(
                label: Text(LapTimesResultMode.absolute.label),
                selected: _resultMode == LapTimesResultMode.absolute,
                onSelected: (_) =>
                    setState(() => _resultMode = LapTimesResultMode.absolute),
              ),
              const SizedBox(width: 6),
              ChoiceChip(
                label: Text(LapTimesResultMode.difference.label),
                selected: _resultMode == LapTimesResultMode.difference,
                onSelected: (_) =>
                    setState(() => _resultMode = LapTimesResultMode.difference),
              ),
              const Spacer(),
              const Text('Hide invalid'),
              Switch(
                value: _hideInvalid,
                onChanged: (value) => setState(() {
                  _hideInvalid = value;
                  _comparisonLapId = null;
                  _selectedLapId = null;
                }),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 240,
                child: DropdownButtonFormField<String>(
                  initialValue: comparisonLap?.id ??
                      (comparisonItems.isNotEmpty
                          ? comparisonItems.first.value
                          : null),
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Comparison Lap',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  items: comparisonItems,
                  onChanged: (value) =>
                      setState(() => _comparisonLapId = value),
                ),
              ),
              SizedBox(
                width: 220,
                child: DropdownButtonFormField<String>(
                  initialValue: selectedLap?.id ??
                      (selectedItems.isNotEmpty
                          ? selectedItems.first.value
                          : null),
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Selected Lap',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  items: selectedItems,
                  onChanged: (value) => setState(() => _selectedLapId = value),
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: !canToggleValidity || _savingLapValidity
                    ? null
                    : () => _toggleLapValidity(
                          selectedLap,
                          nextValid: !selectedLap.valid,
                        ),
                icon: Icon(
                  selectedLap != null && selectedLap.valid
                      ? Icons.block
                      : Icons.verified,
                ),
                label: Text(
                  selectedLap != null && selectedLap.valid
                      ? 'Mark Invalid'
                      : 'Mark Valid',
                ),
              ),
              Text(
                'Showing ${visibleLaps.length} / ${allLaps.length} laps',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSelectedModeWidget({
    required List<LapAnalysisModel> laps,
    required SessionAnalysisSummaryModel? summary,
    required List<CrossingModel> crossings,
    required String? selectedLapId,
    required LapAnalysisModel? comparisonLap,
  }) {
    switch (_selectedMode) {
      case LapTimesMode.sectors:
        return LapTimesSectorsTable(
          laps: laps,
          summary: summary,
          comparisonLap: comparisonLap,
          selectedLapId: selectedLapId,
          resultMode: _resultMode,
          onSelectLap: (lap) => setState(() => _selectedLapId = lap.id),
        );
      case LapTimesMode.splits:
        return LapTimesSplitsTable(
          laps: laps,
          comparisonLap: comparisonLap,
          selectedLapId: selectedLapId,
          resultMode: _resultMode,
          onSelectLap: (lap) => setState(() => _selectedLapId = lap.id),
        );
      case LapTimesMode.trapSpeeds:
        return LapTimesTrapSpeedsTable(
          laps: laps,
          comparisonLap: comparisonLap,
          selectedLapId: selectedLapId,
          resultMode: _resultMode,
          onSelectLap: (lap) => setState(() => _selectedLapId = lap.id),
        );
      case LapTimesMode.highLow:
        return LapTimesHighLowTable(
          laps: laps,
          comparisonLap: comparisonLap,
          selectedLapId: selectedLapId,
          resultMode: _resultMode,
          onSelectLap: (lap) => setState(() => _selectedLapId = lap.id),
        );
      case LapTimesMode.information:
        return LapTimesInformationPanel(
          laps: laps,
          summary: summary,
          crossings: crossings,
        );
    }
  }
}
