import 'package:flutter/material.dart';
import 'package:speed_data/features/models/crossing_model.dart';
import 'package:speed_data/features/models/lap_analysis_model.dart';
import 'package:speed_data/features/models/session_analysis_summary_model.dart';
import 'package:speed_data/features/screens/pilot/widgets/lap_times_high_low_table.dart';
import 'package:speed_data/features/screens/pilot/widgets/lap_times_information_panel.dart';
import 'package:speed_data/features/screens/pilot/widgets/lap_times_splits_table.dart';
import 'package:speed_data/features/screens/pilot/widgets/lap_times_table.dart';
import 'package:speed_data/features/screens/pilot/widgets/lap_times_trap_speeds_table.dart';
import 'package:speed_data/features/services/firestore_service.dart';

enum LapTimesMode {
  sectors,
  splits,
  trapSpeeds,
  highLow,
  information,
}

extension LapTimesModeLabel on LapTimesMode {
  String get label {
    switch (this) {
      case LapTimesMode.sectors:
        return 'Sectors';
      case LapTimesMode.splits:
        return 'Splits';
      case LapTimesMode.trapSpeeds:
        return 'Trap Speeds';
      case LapTimesMode.highLow:
        return 'High/Low';
      case LapTimesMode.information:
        return 'Information';
    }
  }
}

class LapTimesScreen extends StatefulWidget {
  final String raceId;
  final String userId;
  final String raceName;
  final String? eventId;

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

  FirestoreService get _firestore => _localFirestore ??= FirestoreService();

  @override
  void initState() {
    super.initState();
    _selectedMode = widget.initialMode;
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

  void _syncInitialSessionSelection(List<String> sessionIds) {
    if (_didInitializeSessionSelection) return;
    _didInitializeSessionSelection = true;
    if (sessionIds.isEmpty) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _selectedSessionId = sessionIds.first;
      });
    });
  }

  void _clearMissingSession(List<String> sessionIds) {
    if (_selectedSessionId == null) return;
    if (sessionIds.contains(_selectedSessionId)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _selectedSessionId = null;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Lap Times - ${widget.raceName}'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(() {}),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildSessionSelector(),
          _buildModeSelector(),
          if (_selectedSessionId == null)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Text(
                'Legacy mode selected. Session analytics (crossings/summary) may be unavailable.',
              ),
            ),
          Expanded(child: _buildModeContent()),
        ],
      ),
    );
  }

  Widget _buildSessionSelector() {
    return StreamBuilder<List<String>>(
      stream: _sessionIdsStream(),
      builder: (context, snapshot) {
        final sessionIds = snapshot.data ?? const <String>[];
        _syncInitialSessionSelection(sessionIds);
        _clearMissingSession(sessionIds);

        final items = <DropdownMenuItem<String?>>[
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
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: Row(
            children: [
              const Text('Session'),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String?>(
                  initialValue: _selectedSessionId,
                  items: items,
                  onChanged: (value) =>
                      setState(() => _selectedSessionId = value),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildModeSelector() {
    return SizedBox(
      height: 48,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        scrollDirection: Axis.horizontal,
        children: [
          for (final mode in LapTimesMode.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(mode.label),
                selected: _selectedMode == mode,
                onSelected: (_) => setState(() => _selectedMode = mode),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildModeContent() {
    return StreamBuilder<List<LapAnalysisModel>>(
      stream: _lapsStream(_selectedSessionId),
      builder: (context, lapsSnapshot) {
        if (lapsSnapshot.connectionState == ConnectionState.waiting &&
            !lapsSnapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final laps = lapsSnapshot.data ?? const <LapAnalysisModel>[];

        return StreamBuilder<SessionAnalysisSummaryModel?>(
          stream: _summaryStream(_selectedSessionId),
          builder: (context, summarySnapshot) {
            final summary = summarySnapshot.data;
            return StreamBuilder<List<CrossingModel>>(
              stream: _crossingsStream(_selectedSessionId),
              builder: (context, crossingsSnapshot) {
                final crossings =
                    crossingsSnapshot.data ?? const <CrossingModel>[];
                return _buildSelectedModeWidget(
                  laps: laps,
                  summary: summary,
                  crossings: crossings,
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildSelectedModeWidget({
    required List<LapAnalysisModel> laps,
    required SessionAnalysisSummaryModel? summary,
    required List<CrossingModel> crossings,
  }) {
    switch (_selectedMode) {
      case LapTimesMode.sectors:
        return LapTimesSectorsTable(
          laps: laps,
          summary: summary,
        );
      case LapTimesMode.splits:
        return LapTimesSplitsTable(laps: laps);
      case LapTimesMode.trapSpeeds:
        return LapTimesTrapSpeedsTable(laps: laps);
      case LapTimesMode.highLow:
        return LapTimesHighLowTable(laps: laps);
      case LapTimesMode.information:
        return LapTimesInformationPanel(
          laps: laps,
          summary: summary,
          crossings: crossings,
        );
    }
  }
}
