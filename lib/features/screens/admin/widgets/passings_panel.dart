import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:speed_data/features/models/competitor_model.dart';
import 'package:speed_data/features/models/passing_model.dart';
import 'package:speed_data/features/models/race_session_model.dart';
import 'package:speed_data/features/services/firestore_service.dart';
import 'package:speed_data/theme/speed_data_theme.dart';

class _LapAggregate {
  final String participantUid;
  final String name;
  final int lapNumber;
  DateTime firstTime;
  DateTime? startTime;
  DateTime? finishTime;
  double? lapTimeMs;
  bool hasStarted = false;
  final Map<int, double> sectorByIndex = {};
  final Set<String> flags = {};

  _LapAggregate({
    required this.participantUid,
    required this.name,
    required this.lapNumber,
    required this.firstTime,
  });
}

class _LapListEntry {
  final DateTime time;
  final _LapAggregate? lap;
  final PassingModel? flagPassing;

  _LapListEntry({
    required this.time,
    this.lap,
    this.flagPassing,
  });

  bool get isFlag => flagPassing != null;
}

class PassingsPanel extends StatefulWidget {
  final String raceId;
  final String? eventId;
  final String? sessionId;
  final SessionType sessionType;
  final RaceSession? session;
  final Map<String, Competitor> competitorsByUid;

  const PassingsPanel({
    Key? key,
    required this.raceId,
    this.eventId,
    this.sessionId,
    required this.sessionType,
    this.session,
    this.competitorsByUid = const {},
  }) : super(key: key);

  @override
  State<PassingsPanel> createState() => _PassingsPanelState();
}

class _PassingsPanelState extends State<PassingsPanel> {
  final ScrollController _verticalScrollController = ScrollController();
  final ScrollController _horizontalScrollController = ScrollController();
  final Map<String, String> _competitorNameCache = {};
  static const double _timeColWidth = 90;
  static const double _nameColWidth = 220;
  static const double _lapColWidth = 44;
  static const double _lapTimeColWidth = 90;
  static const double _sectorColWidth = 90;
  static const double _rowPaddingHorizontal = 8;

  @override
  void initState() {
    super.initState();
    _loadCompetitorNames();
  }

  @override
  void didUpdateWidget(covariant PassingsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.eventId != widget.eventId ||
        oldWidget.raceId != widget.raceId) {
      _loadCompetitorNames();
    }
  }

  Future<void> _loadCompetitorNames() async {
    String? eventId = widget.eventId;
    if (eventId == null || eventId.isEmpty) {
      final event =
          await FirestoreService().getActiveEventForTrack(widget.raceId);
      eventId = event?.id;
    }
    if (eventId == null || eventId.isEmpty) return;
    try {
      final competitors = await FirestoreService().getCompetitors(eventId);
      if (!mounted) return;
      setState(() {
        for (final c in competitors) {
          if (c.uid.isEmpty) continue;
          final fullName = '${c.firstName} ${c.lastName}'.trim();
          _competitorNameCache[c.uid] =
              fullName.isNotEmpty ? fullName : 'Unknown';
        }
      });
    } catch (e) {
      debugPrint('Error loading competitor names: $e');
    }
  }

  @override
  void dispose() {
    _verticalScrollController.dispose();
    _horizontalScrollController.dispose();
    super.dispose();
  }

  String _resolveCompetitorName(PassingModel passing) {
    final uid = passing.participantUid;
    if (uid.isEmpty) return 'Unknown';

    final competitor = widget.competitorsByUid[uid];
    if (competitor != null && competitor.name.isNotEmpty)
      return competitor.name;

    final cachedName = _competitorNameCache[uid];
    if (cachedName != null && cachedName != 'Loading...') return cachedName;

    final fallbackName = passing.driverName.trim();
    if (fallbackName.isNotEmpty && fallbackName != 'Unknown')
      return fallbackName;

    return uid;
  }

  String _formatDuration(num? ms) {
    if (ms == null) return '--:--.---';
    final duration = Duration(milliseconds: ms.toInt());
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    final millis =
        (duration.inMilliseconds.remainder(1000)).toString().padLeft(3, '0');
    return '$minutes:$seconds.$millis';
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<PassingModel>>(
      stream: FirestoreService().getPassingsStream(
        widget.raceId,
        sessionId: widget.sessionId,
        eventId: widget.eventId,
        session: widget.session,
      ),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Error loading laps: ${snapshot.error}',
              style: const TextStyle(color: SpeedDataTheme.textSecondary),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final passings = snapshot.data!
          ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
        final lapMap = <String, _LapAggregate>{};

        for (final p in passings) {
          if (p.participantUid == 'SYSTEM') continue;
          final key = '${p.participantUid}_${p.lapNumber}';
          final agg = lapMap.putIfAbsent(
            key,
            () => _LapAggregate(
              participantUid: p.participantUid,
              name: _resolveCompetitorName(p),
              lapNumber: p.lapNumber,
              firstTime: p.timestamp,
            ),
          );

          if (p.timestamp.isBefore(agg.firstTime)) {
            agg.firstTime = p.timestamp;
          }
          if (p.checkpointIndex == 0) {
            agg.hasStarted = true;
            if (agg.startTime == null || p.timestamp.isBefore(agg.startTime!)) {
              agg.startTime = p.timestamp;
            }
          }
          agg.flags.addAll(p.flags.map((f) => f.toLowerCase()));
          if (p.checkpointIndex > 0 && p.sectorTime != null) {
            agg.sectorByIndex[p.checkpointIndex] = p.sectorTime!;
          }
          if (p.lapTime != null) {
            agg.lapTimeMs = p.lapTime;
            agg.finishTime = p.timestamp;
          }
        }

        final laps = lapMap.values
            .where((l) => l.hasStarted || l.lapTimeMs != null)
            .toList()
          ..sort((a, b) {
            final at = a.finishTime ?? a.firstTime;
            final bt = b.finishTime ?? b.firstTime;
            return at.compareTo(bt);
          });
        final flagPassings = passings
            .where((p) => p.participantUid == 'SYSTEM')
            .where(
                (p) => p.flags.any((f) => f.toLowerCase().startsWith('flag_')))
            .toList()
          ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

        int maxSector = 0;
        for (final lap in laps) {
          for (final sector in lap.sectorByIndex.keys) {
            if (sector > maxSector) maxSector = sector;
          }
        }
        if (maxSector == 0 && passings.isNotEmpty) {
          final fromCheckpoint = passings
              .where((p) => p.participantUid != 'SYSTEM')
              .map((p) => p.checkpointIndex)
              .fold<int>(0, (acc, v) => v > acc ? v : acc);
          if (fromCheckpoint > 0) {
            maxSector = fromCheckpoint;
          }
        }

        final minLapMs = (widget.session?.minLapTimeSeconds ?? 0) * 1000.0;
        final tableWidth = (_rowPaddingHorizontal * 2) +
            _timeColWidth +
            _nameColWidth +
            _lapColWidth +
            _lapTimeColWidth +
            (_sectorColWidth * maxSector);
        final entries = <_LapListEntry>[
          ...flagPassings
              .map((p) => _LapListEntry(time: p.timestamp, flagPassing: p)),
          ...laps.map(
              (l) => _LapListEntry(time: l.startTime ?? l.firstTime, lap: l)),
        ]..sort((a, b) => a.time.compareTo(b.time));
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_verticalScrollController.hasClients) {
            _verticalScrollController
                .jumpTo(_verticalScrollController.position.maxScrollExtent);
          }
        });

        return Container(
          color: SpeedDataTheme.bgSurface,
          child: Scrollbar(
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
                    _buildHeader(maxSector),
                    const Divider(height: 1, color: SpeedDataTheme.borderColor),
                    Expanded(
                      child: Scrollbar(
                        controller: _verticalScrollController,
                        thumbVisibility: true,
                        child: ListView.separated(
                          controller: _verticalScrollController,
                          itemCount: entries.length,
                          separatorBuilder: (_, __) => const Divider(
                              height: 1, color: SpeedDataTheme.borderSubtle),
                          itemBuilder: (context, index) {
                            final entry = entries[index];
                            if (entry.isFlag) {
                              final flagPassing = entry.flagPassing!;
                              Color flagColor = Colors.grey;
                              final flags = flagPassing.flags
                                  .map((e) => e.toLowerCase())
                                  .toSet();
                              if (flags.contains('flag_green')) {
                                flagColor = SpeedDataTheme.flagGreen;
                              } else if (flags.contains('flag_warmup')) {
                                flagColor = SpeedDataTheme.flagPurple;
                              } else if (flags.contains('flag_yellow')) {
                                flagColor = SpeedDataTheme.flagYellow;
                              } else if (flags.contains('flag_red')) {
                                flagColor = SpeedDataTheme.flagRed;
                              } else if (flags.contains('flag_checkered')) {
                                flagColor = Colors.white;
                              }

                              return Container(
                                color: flagColor.withValues(alpha: 0.15),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 6),
                                child: Row(
                                  children: [
                                    SizedBox(
                                      width: _timeColWidth,
                                      child: Text(
                                        DateFormat('HH:mm:ss.SSS')
                                            .format(entry.time),
                                        style: const TextStyle(
                                          fontFamily: 'monospace',
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    SizedBox(
                                      width: tableWidth - _timeColWidth - 16,
                                      child: Text(
                                        flagPassing.driverName,
                                        style: TextStyle(
                                          color: flagColor == Colors.white
                                              ? Colors.white
                                              : flagColor,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }

                            final lap = entry.lap!;
                            final isDeleted = lap.flags.contains('deleted');
                            final isInvalid = lap.flags.contains('invalid') ||
                                (lap.lapTimeMs != null &&
                                    lap.lapTimeMs! < minLapMs &&
                                    minLapMs > 0);

                            final baseColor = isDeleted || isInvalid
                                ? SpeedDataTheme.flagRed
                                : SpeedDataTheme.textPrimary;

                            final rowColor = isDeleted
                                ? Colors.grey.shade900
                                : (isInvalid
                                    ? SpeedDataTheme.flagRed
                                        .withValues(alpha: 0.12)
                                    : Colors.transparent);

                            final time = lap.startTime ?? lap.firstTime;
                            return Container(
                              color: rowColor,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 6),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: _timeColWidth,
                                    child: Text(
                                      DateFormat('HH:mm:ss.SSS').format(time),
                                      style: TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 12,
                                        color: baseColor,
                                      ),
                                    ),
                                  ),
                                  SizedBox(
                                    width: _nameColWidth,
                                    child: Text(
                                      lap.name,
                                      style: TextStyle(
                                          fontSize: 12, color: baseColor),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  SizedBox(
                                    width: _lapColWidth,
                                    child: Text(
                                      lap.lapNumber.toString(),
                                      style: TextStyle(
                                          fontSize: 12, color: baseColor),
                                    ),
                                  ),
                                  SizedBox(
                                    width: _lapTimeColWidth,
                                    child: Text(
                                      _formatDuration(lap.lapTimeMs),
                                      style: TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 12,
                                        color: baseColor,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  for (int sector = 1;
                                      sector <= maxSector;
                                      sector++)
                                    SizedBox(
                                      width: _sectorColWidth,
                                      child: Text(
                                        _formatDuration(
                                            lap.sectorByIndex[sector]),
                                        style: const TextStyle(
                                          fontFamily: 'monospace',
                                          fontSize: 11,
                                          color: SpeedDataTheme.textSecondary,
                                        ),
                                      ),
                                    ),
                                ],
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
          ),
        );
      },
    );
  }

  Widget _buildHeader(int maxSector) {
    return Container(
      color: SpeedDataTheme.bgElevated,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            const SizedBox(
              width: _timeColWidth,
              child: Text('TIME',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            ),
            const SizedBox(
              width: _nameColWidth,
              child: Text('NAME',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            ),
            const SizedBox(
              width: _lapColWidth,
              child: Text('LAP',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            ),
            const SizedBox(
              width: _lapTimeColWidth,
              child: Text('LAP TIME',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            ),
            for (int sector = 1; sector <= maxSector; sector++)
              SizedBox(
                width: _sectorColWidth,
                child: Text(
                  'S$sector',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
