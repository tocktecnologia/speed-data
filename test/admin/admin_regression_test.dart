import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:speed_data/features/models/competitor_model.dart';
import 'package:speed_data/features/models/lap_analysis_model.dart';
import 'package:speed_data/features/models/passing_model.dart';
import 'package:speed_data/features/models/race_session_model.dart';
import 'package:speed_data/features/models/session_analysis_summary_model.dart';
import 'package:speed_data/features/screens/admin/widgets/control_flags.dart';
import 'package:speed_data/features/screens/admin/widgets/leaderboard_panel.dart';
import 'package:speed_data/features/screens/admin/widgets/passings_panel.dart';

Widget _wrapForTest(Widget child) {
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

RaceSession _buildSession({
  String id = 'session_1',
  SessionType type = SessionType.race,
  SessionStatus status = SessionStatus.active,
  int minLapTimeSeconds = 0,
}) {
  return RaceSession(
    id: id,
    type: type,
    status: status,
    scheduledTime: DateTime(2026, 1, 1, 10, 0),
    minLapTimeSeconds: minLapTimeSeconds,
  );
}

Competitor _competitor({
  required String id,
  required String uid,
  required String number,
  required String firstName,
  required String lastName,
}) {
  return Competitor(
    id: id,
    groupId: 'g1',
    firstName: firstName,
    lastName: lastName,
    number: number,
    uid: uid,
  );
}

LapAnalysisModel _lap({
  required String id,
  required int number,
  required int totalLapTimeMs,
  required bool valid,
  required List<int> sectorsMs,
}) {
  final start = number * 100000;
  return LapAnalysisModel(
    id: id,
    number: number,
    lapStartMs: start,
    lapEndMs: start + totalLapTimeMs,
    totalLapTimeMs: totalLapTimeMs,
    valid: valid,
    invalidReasons: valid ? const [] : const ['invalid'],
    splitsMs: sectorsMs,
    sectorsMs: sectorsMs,
    trapSpeedsMps: const [40.0],
  );
}

PassingModel _passing({
  required String id,
  required String uid,
  required DateTime timestamp,
  required int checkpoint,
  required int lap,
  String driverName = '',
  List<String> flags = const [],
  double? lapTime,
  double? sectorTime,
  double? splitTime,
  double? trapSpeed,
}) {
  return PassingModel(
    id: id,
    raceId: 'race_1',
    eventId: 'event_1',
    sessionId: 'session_1',
    participantUid: uid,
    driverName: driverName.isEmpty ? uid : driverName,
    carNumber: '11',
    timestamp: timestamp,
    checkpointIndex: checkpoint,
    lapNumber: lap,
    lapTime: lapTime,
    sectorTime: sectorTime,
    splitTime: splitTime,
    trapSpeed: trapSpeed,
    flags: flags,
  );
}

void main() {
  testWidgets('ControlFlags envia a bandeira correta ao clicar',
      (WidgetTester tester) async {
    RaceFlag? selected;

    await tester.pumpWidget(
      _wrapForTest(
        ControlFlags(
          currentFlag: RaceFlag.green,
          onFlagSelected: (flag) => selected = flag,
        ),
      ),
    );

    expect(find.byIcon(Icons.flag), findsNWidgets(5));

    await tester.tap(find.byIcon(Icons.flag).at(3));
    await tester.pump();

    expect(selected, RaceFlag.red);
  });

  testWidgets(
      'PassingsPanel mostra dados novos de split/trap/sector e mantem legado',
      (WidgetTester tester) async {
    final now = DateTime(2026, 2, 19, 12, 0, 0);
    final passings = <PassingModel>[
      _passing(
        id: 'flag_1',
        uid: 'SYSTEM',
        driverName: 'GREEN FLAG',
        timestamp: now,
        checkpoint: -1,
        lap: 0,
        flags: const ['flag_green'],
      ),
      _passing(
        id: 'p_start',
        uid: 'uid_a',
        driverName: 'Alpha Driver',
        timestamp: now.add(const Duration(seconds: 3)),
        checkpoint: 0,
        lap: 1,
      ),
      _passing(
        id: 'p_split_1',
        uid: 'uid_a',
        driverName: 'Alpha Driver',
        timestamp: now.add(const Duration(seconds: 20)),
        checkpoint: 1,
        lap: 1,
        sectorTime: 20000,
        splitTime: 20000,
        trapSpeed: 41.5,
      ),
      _passing(
        id: 'p_finish',
        uid: 'uid_a',
        driverName: 'Alpha Driver',
        timestamp: now.add(const Duration(seconds: 55)),
        checkpoint: 2,
        lap: 1,
        sectorTime: 35000,
        splitTime: 55000,
        trapSpeed: 42.3,
        lapTime: 60000,
      ),
      // Lap legado sem split/trap para garantir fallback visual
      _passing(
        id: 'legacy_start',
        uid: 'uid_b',
        driverName: 'Beta Driver',
        timestamp: now.add(const Duration(minutes: 2)),
        checkpoint: 0,
        lap: 1,
      ),
      _passing(
        id: 'legacy_finish',
        uid: 'uid_b',
        driverName: 'Beta Driver',
        timestamp: now.add(const Duration(minutes: 3, seconds: 15)),
        checkpoint: 0,
        lap: 1,
        lapTime: 75000,
      ),
    ];

    await tester.pumpWidget(
      _wrapForTest(
        PassingsPanel(
          raceId: 'race_1',
          eventId: 'event_1',
          sessionId: 'session_1',
          sessionType: SessionType.race,
          session: _buildSession(id: 'session_1'),
          passingsStream: Stream<List<PassingModel>>.value(passings),
          competitorsByUid: {
            'uid_a': _competitor(
              id: 'c1',
              uid: 'uid_a',
              number: '11',
              firstName: 'Alpha',
              lastName: 'Driver',
            ),
            'uid_b': _competitor(
              id: 'c2',
              uid: 'uid_b',
              number: '22',
              firstName: 'Beta',
              lastName: 'Driver',
            ),
          },
          competitorsLoader: (_) async => const [],
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('GREEN FLAG'), findsOneWidget);
    expect(find.text('SPLIT'), findsOneWidget);
    expect(find.text('TRAP'), findsOneWidget);
    expect(find.text('S1'), findsOneWidget);
    expect(find.text('S2'), findsOneWidget);
    expect(find.text('00:55.000'), findsOneWidget);
    expect(find.text('42.3'), findsOneWidget);
    expect(find.text('--:--.---'), findsWidgets);
    expect(find.text('--.-'), findsWidgets);
  });

  testWidgets(
      'LeaderboardPanel prioriza resumo derivado de voltas validas sobre summary externo',
      (WidgetTester tester) async {
    final competitorsByUid = {
      'uid_a': _competitor(
        id: 'c1',
        uid: 'uid_a',
        number: '11',
        firstName: 'Alpha',
        lastName: 'Driver',
      ),
      'uid_b': _competitor(
        id: 'c2',
        uid: 'uid_b',
        number: '22',
        firstName: 'Beta',
        lastName: 'Driver',
      ),
    };

    final lapsByUid = <String, List<LapAnalysisModel>>{
      'uid_a': [
        _lap(
          id: 'a1',
          number: 1,
          totalLapTimeMs: 62000,
          valid: true,
          sectorsMs: const [30000, 32000],
        ),
        _lap(
          id: 'a2',
          number: 2,
          totalLapTimeMs: 58000,
          valid: false,
          sectorsMs: const [28000, 30000],
        ),
      ],
      'uid_b': [
        _lap(
          id: 'b1',
          number: 1,
          totalLapTimeMs: 60000,
          valid: true,
          sectorsMs: const [29000, 31000],
        ),
      ],
    };

    final conflictingBackendSummary = SessionAnalysisSummaryModel(
      bestLapMs: 58000,
      optimalLapMs: 56000,
      bestSectorsMs: const [28000, 28000],
      validLapsCount: 3,
      totalLapsCount: 3,
    );

    await tester.pumpWidget(
      _wrapForTest(
        LeaderboardPanel(
          raceId: 'race_1',
          eventId: 'event_1',
          sessionId: 'session_1',
          checkpoints: const [],
          sessionType: SessionType.qualifying,
          session: _buildSession(
            id: 'session_1',
            type: SessionType.qualifying,
            minLapTimeSeconds: 0,
          ),
          competitorsByUid: competitorsByUid,
          disableParticipantsSubscription: true,
          passingsStream: const Stream<List<PassingModel>>.empty(),
          sessionLapsStream:
              Stream<Map<String, List<LapAnalysisModel>>>.value(lapsByUid),
          sessionSummaryStream: Stream<SessionAnalysisSummaryModel?>.value(
              conflictingBackendSummary),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('best_lap: 1:00.000'), findsOneWidget);
    expect(find.text('optimal_lap: 1:00.000'), findsOneWidget);
    expect(find.text('best_lap: 0:58.000'), findsNothing);
    expect(find.textContaining('+2.000'), findsNWidgets(2));
    expect(find.text('Beta Driver'), findsOneWidget);
    expect(find.text('Alpha Driver'), findsOneWidget);
  });

  testWidgets('LeaderboardPanel atualiza resultado ao trocar sessionId',
      (WidgetTester tester) async {
    final competitorsByUid = {
      'uid_a': _competitor(
        id: 'c1',
        uid: 'uid_a',
        number: '11',
        firstName: 'Alpha',
        lastName: 'Driver',
      ),
      'uid_b': _competitor(
        id: 'c2',
        uid: 'uid_b',
        number: '22',
        firstName: 'Beta',
        lastName: 'Driver',
      ),
    };

    await tester.pumpWidget(
      _wrapForTest(
        LeaderboardPanel(
          raceId: 'race_1',
          eventId: 'event_1',
          sessionId: 'session_1',
          checkpoints: const [],
          sessionType: SessionType.qualifying,
          session: _buildSession(id: 'session_1', type: SessionType.qualifying),
          competitorsByUid: competitorsByUid,
          disableParticipantsSubscription: true,
          passingsStream: const Stream<List<PassingModel>>.empty(),
          sessionLapsStream: Stream<Map<String, List<LapAnalysisModel>>>.value({
            'uid_a': [
              _lap(
                id: 's1_a1',
                number: 1,
                totalLapTimeMs: 62000,
                valid: true,
                sectorsMs: const [31000, 31000],
              ),
            ],
          }),
          sessionSummaryStream:
              Stream<SessionAnalysisSummaryModel?>.value(null),
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.text('best_lap: 1:02.000'), findsOneWidget);

    await tester.pumpWidget(
      _wrapForTest(
        LeaderboardPanel(
          raceId: 'race_1',
          eventId: 'event_1',
          sessionId: 'session_2',
          checkpoints: const [],
          sessionType: SessionType.qualifying,
          session: _buildSession(id: 'session_2', type: SessionType.qualifying),
          competitorsByUid: competitorsByUid,
          disableParticipantsSubscription: true,
          passingsStream: const Stream<List<PassingModel>>.empty(),
          sessionLapsStream: Stream<Map<String, List<LapAnalysisModel>>>.value({
            'uid_b': [
              _lap(
                id: 's2_b1',
                number: 1,
                totalLapTimeMs: 59000,
                valid: true,
                sectorsMs: const [29000, 30000],
              ),
            ],
          }),
          sessionSummaryStream:
              Stream<SessionAnalysisSummaryModel?>.value(null),
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.text('best_lap: 0:59.000'), findsOneWidget);
    expect(find.text('best_lap: 1:02.000'), findsNothing);
  });
}
