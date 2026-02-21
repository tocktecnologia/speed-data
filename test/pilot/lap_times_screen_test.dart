import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:speed_data/features/models/crossing_model.dart';
import 'package:speed_data/features/models/lap_analysis_model.dart';
import 'package:speed_data/features/models/session_analysis_summary_model.dart';
import 'package:speed_data/features/screens/pilot/lap_times_screen.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 1400,
        height: 900,
        child: child,
      ),
    ),
  );
}

LapAnalysisModel _lap({
  required String id,
  required int number,
  required int totalMs,
  required bool valid,
  required List<int> sectors,
  required List<int> splits,
  required List<double> traps,
}) {
  final start = number * 100000;
  return LapAnalysisModel(
    id: id,
    number: number,
    lapStartMs: start,
    lapEndMs: start + totalMs,
    totalLapTimeMs: totalMs,
    valid: valid,
    invalidReasons: valid ? const [] : const ['invalid'],
    splitsMs: splits,
    sectorsMs: sectors,
    trapSpeedsMps: traps,
    speedStats: SpeedStats(
      minMps: traps.isEmpty ? 0 : traps.reduce((a, b) => a < b ? a : b),
      maxMps: traps.isEmpty ? 0 : traps.reduce((a, b) => a > b ? a : b),
      avgMps: traps.isEmpty
          ? 0
          : traps.reduce((sum, value) => sum + value) / traps.length,
    ),
  );
}

CrossingModel _crossing({
  required String id,
  required int lap,
  required int checkpoint,
  required int crossedAtMs,
}) {
  return CrossingModel(
    id: id,
    lapNumber: lap,
    checkpointIndex: checkpoint,
    crossedAtMs: crossedAtMs,
    speedMps: 35.0,
    lat: 0,
    lng: 0,
    method: 'test',
    distanceToCheckpointM: 0,
    confidence: 1.0,
    sectorTimeMs: checkpoint > 0 ? 1000 * checkpoint : null,
    splitTimeMs: 1000 * checkpoint,
  );
}

void main() {
  final laps = <LapAnalysisModel>[
    _lap(
      id: 'l1',
      number: 1,
      totalMs: 62000,
      valid: true,
      sectors: const [30000, 32000],
      splits: const [0, 30000, 62000],
      traps: const [30.1, 32.3, 35.0],
    ),
    _lap(
      id: 'l2',
      number: 2,
      totalMs: 58000,
      valid: false,
      sectors: const [28000, 30000],
      splits: const [0, 28000, 58000],
      traps: const [31.0, 33.5, 36.2],
    ),
    _lap(
      id: 'l3',
      number: 3,
      totalMs: 60000,
      valid: true,
      sectors: const [29000, 31000],
      splits: const [0, 29000, 60000],
      traps: const [30.5, 34.0, 36.0],
    ),
  ];

  final summary = SessionAnalysisSummaryModel(
    bestLapMs: 60000,
    optimalLapMs: 60000,
    bestSectorsMs: const [29000, 31000],
    validLapsCount: 2,
    totalLapsCount: 3,
  );

  final crossings = <CrossingModel>[
    _crossing(id: 'c1', lap: 1, checkpoint: 0, crossedAtMs: 1000),
    _crossing(id: 'c2', lap: 1, checkpoint: 1, crossedAtMs: 31000),
    _crossing(id: 'c3', lap: 1, checkpoint: 2, crossedAtMs: 62000),
  ];

  testWidgets('renders sectors mode with OPT row and reference lap',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      _wrap(
        LapTimesScreen(
          raceId: 'race_1',
          userId: 'uid_1',
          raceName: 'Race A',
          sessionIdsStreamOverride:
              Stream<List<String>>.value(const ['session_1']),
          lapsStreamBuilder: (_) => Stream<List<LapAnalysisModel>>.value(laps),
          summaryStreamBuilder: (_) =>
              Stream<SessionAnalysisSummaryModel?>.value(summary),
          crossingsStreamBuilder: (_) =>
              Stream<List<CrossingModel>>.value(crossings),
        ),
      ),
    );

    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Sectors'), findsOneWidget);
    expect(find.text('OPT'), findsOneWidget);
    expect(find.textContaining('Reference lap: L3'), findsOneWidget);
    expect(find.text('S1'), findsOneWidget);
    expect(find.text('S2'), findsOneWidget);
  });

  testWidgets('switches between all Lap Times modes',
      (WidgetTester tester) async {
    Future<void> tapMode(String label) async {
      final chipFinder = find.byWidgetPredicate(
        (widget) =>
            widget is ChoiceChip &&
            widget.label is Text &&
            (widget.label as Text).data == label,
      );
      expect(chipFinder, findsWidgets);
      await tester.ensureVisible(chipFinder.first);
      await tester.tap(chipFinder.first);
      await tester.pumpAndSettle();
    }

    await tester.pumpWidget(
      _wrap(
        LapTimesScreen(
          raceId: 'race_1',
          userId: 'uid_1',
          raceName: 'Race A',
          sessionIdsStreamOverride:
              Stream<List<String>>.value(const ['session_1']),
          lapsStreamBuilder: (_) => Stream<List<LapAnalysisModel>>.value(laps),
          summaryStreamBuilder: (_) =>
              Stream<SessionAnalysisSummaryModel?>.value(summary),
          crossingsStreamBuilder: (_) =>
              Stream<List<CrossingModel>>.value(crossings),
        ),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    await tapMode('Splits');
    expect(find.text('SP1'), findsOneWidget);

    await tapMode('Trap Speeds');
    expect(find.text('Peak'), findsOneWidget);
    expect(find.text('TP1'), findsOneWidget);

    await tapMode('High/Low');
    expect(find.text('Range'), findsOneWidget);

    await tapMode('Information');
    expect(find.text('Session Summary'), findsOneWidget);
  });

  testWidgets('ignores invalid laps when selecting sectors reference',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      _wrap(
        LapTimesScreen(
          raceId: 'race_1',
          userId: 'uid_1',
          raceName: 'Race A',
          sessionIdsStreamOverride:
              Stream<List<String>>.value(const ['session_1']),
          lapsStreamBuilder: (_) => Stream<List<LapAnalysisModel>>.value(laps),
          summaryStreamBuilder: (_) =>
              Stream<SessionAnalysisSummaryModel?>.value(summary),
          crossingsStreamBuilder: (_) =>
              Stream<List<CrossingModel>>.value(crossings),
        ),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    // Lap 2 is faster but invalid, so reference must remain valid lap L3.
    expect(find.textContaining('Reference lap: L3'), findsOneWidget);
    expect(find.textContaining('Reference lap: L2'), findsNothing);
  });

  testWidgets('shows legacy notice when there are no session ids',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      _wrap(
        LapTimesScreen(
          raceId: 'race_1',
          userId: 'uid_1',
          raceName: 'Race A',
          sessionIdsStreamOverride: Stream<List<String>>.value(const []),
          lapsStreamBuilder: (_) => Stream<List<LapAnalysisModel>>.value(laps),
          summaryStreamBuilder: (_) =>
              Stream<SessionAnalysisSummaryModel?>.value(null),
          crossingsStreamBuilder: (_) =>
              Stream<List<CrossingModel>>.value(const []),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Legacy mode selected'), findsOneWidget);
  });
}
