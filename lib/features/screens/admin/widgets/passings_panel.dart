import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:speed_data/features/models/race_session_model.dart';
import 'package:intl/intl.dart';
import 'package:speed_data/theme/speed_data_theme.dart';
import 'package:speed_data/features/services/firestore_service.dart';
import 'package:speed_data/features/models/passing_model.dart';
import 'package:speed_data/features/models/competitor_model.dart';

class PassingsPanel extends StatefulWidget {
  final String raceId;
  final String? sessionId;
  final SessionType sessionType;
  final RaceSession? session; // Added for time-based filtering
  final Map<String, Competitor> competitorsByUid;

  const PassingsPanel({
    Key? key,
    required this.raceId,
    this.sessionId,
    required this.sessionType,
    this.session,
    this.competitorsByUid = const {},
  }) : super(key: key);

  @override
  State<PassingsPanel> createState() => _PassingsPanelState();
}

class _PassingsPanelState extends State<PassingsPanel> {
  final ScrollController _scrollController = ScrollController();
  final Map<String, String> _competitorNameCache = {}; // Cache: uid -> name
  String? _currentEventId;

  @override
  void initState() {
    super.initState();
    _loadEventId();
  }

  Future<void> _loadEventId() async {
    // Get event ID for this track to fetch competitors
    final event =
        await FirestoreService().getActiveEventForTrack(widget.raceId);
    if (event != null && mounted) {
      setState(() {
        _currentEventId = event.id;
      });
      _loadCompetitorNames(event.id);
    }
  }

  Future<void> _loadCompetitorNames(String eventId) async {
    // Pre-load all competitor names for this event
    try {
      final competitors = await FirestoreService().getCompetitors(eventId);
      if (mounted) {
        setState(() {
          for (final competitor in competitors) {
            if (competitor.uid.isNotEmpty) {
              final fullName =
                  '${competitor.firstName} ${competitor.lastName}'.trim();
              _competitorNameCache[competitor.uid] =
                  fullName.isNotEmpty ? fullName : 'Unknown';
            }
          }
        });
      }
    } catch (e) {
      debugPrint('Error loading competitor names: $e');
    }
  }

  String _getCompetitorName(String uid) {
    return _competitorNameCache[uid] ?? 'Loading...';
  }

  String _resolveCompetitorName(PassingModel passing) {
    final uid = passing.participantUid;
    if (uid.isEmpty) return 'Unknown';

    final competitor = widget.competitorsByUid[uid];
    if (competitor != null) {
      final displayName = competitor.name;
      if (displayName.isNotEmpty) return displayName;
    }

    final cachedName = _competitorNameCache[uid];
    if (cachedName != null && cachedName != 'Loading...') return cachedName;

    final fallbackName = passing.driverName.trim();
    if (fallbackName.isNotEmpty && fallbackName != 'Unknown') {
      _competitorNameCache[uid] = fallbackName;
      return fallbackName;
    }

    return uid;
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  String _formatDuration(double? ms) {
    if (ms == null) return '--:--:--';
    final duration = Duration(milliseconds: ms.toInt());
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    final milliseconds =
        (duration.inMilliseconds.remainder(1000)).toString().padLeft(3, '0');
    return '$minutes:$seconds.$milliseconds';
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<PassingModel>>(
      stream: FirestoreService().getPassingsStream(widget.raceId,
          sessionId: widget.sessionId, session: widget.session),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          debugPrint('PassingsPanel Error: ${snapshot.error}');
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline,
                      color: SpeedDataTheme.flagRed, size: 32),
                  const SizedBox(height: 8),
                  Text('Error loading passings: ${snapshot.error}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: SpeedDataTheme.textSecondary, fontSize: 12)),
                ],
              ),
            ),
          );
        }
        if (!snapshot.hasData)
          return const Center(child: CircularProgressIndicator());

        final passings = snapshot.data!;
        final minLapMs = (widget.session?.minLapTimeSeconds ?? 0) * 1000.0;
        final bestLapTimeByParticipant = <String, double>{};
        for (final passing in passings) {
          final participantUid = passing.participantUid;
          if (participantUid == 'SYSTEM') continue;
          final flags = passing.flags.map((flag) => flag.toLowerCase()).toSet();
          if (flags.contains('invalid') || flags.contains('deleted')) continue;
          if (passing.lapTime == null || passing.lapTime! <= 0) continue;
          if (minLapMs > 0 && passing.lapTime! < minLapMs) continue;
          bestLapTimeByParticipant.update(
            participantUid,
            (current) => math.min(current, passing.lapTime!),
            ifAbsent: () => passing.lapTime!,
          );
        }

        // Calculate lap numbers dynamically: track lap number for each passing
        final Map<String, int> currentLapPerCompetitor = {};
        final List<int> calculatedLapNumbers = [];

        for (int i = 0; i < passings.length; i++) {
          final passing = passings[i];
          if (passing.participantUid == 'SYSTEM') {
            calculatedLapNumbers
                .add(0); // System messages don't have lap numbers
          } else {
            // Increment lap count for this competitor
            currentLapPerCompetitor[passing.participantUid] =
                (currentLapPerCompetitor[passing.participantUid] ?? 0) + 1;
            calculatedLapNumbers
                .add(currentLapPerCompetitor[passing.participantUid]!);
          }
        }

        // Auto-scroll to bottom after frame
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

        return Container(
          color: SpeedDataTheme.bgSurface,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Table Header
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                color: SpeedDataTheme.bgElevated,
                child: Row(
                  children: const [
                    SizedBox(
                        width: 80,
                        child: Text('TIME',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 12))),
                    SizedBox(
                        width: 50,
                        child: Text('#',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 12))),
                    Expanded(
                        child: Text('NAME',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 12))),
                    SizedBox(
                        width: 40,
                        child: Text('LAP',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 12))),
                    SizedBox(
                        width: 80,
                        child: Text('LAP TIME',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 12))),
                    SizedBox(
                        width: 80,
                        child: Text('SECTOR',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 12))),
                    SizedBox(
                        width: 30, child: Icon(Icons.battery_std, size: 14)),
                  ],
                ),
              ),
              const Divider(height: 1, color: SpeedDataTheme.borderColor),
              Expanded(
                child: ListView.separated(
                  controller: _scrollController,
                  itemCount: passings.length,
                  separatorBuilder: (context, index) => const Divider(
                      height: 1, color: SpeedDataTheme.borderSubtle),
                  itemBuilder: (context, index) {
                    final passing = passings[index];
                    final timeStr =
                        DateFormat('HH:mm:ss.SSS').format(passing.timestamp);

                    // Check for System Flags
                    if (passing.participantUid == 'SYSTEM') {
                      Color flagColor = Colors.grey;
                      if (passing.flags.contains('flag_green'))
                        flagColor = SpeedDataTheme.flagGreen;
                      else if (passing.flags.contains('flag_warmup'))
                        flagColor = SpeedDataTheme.flagPurple;
                      else if (passing.flags.contains('flag_yellow'))
                        flagColor = SpeedDataTheme.flagYellow;
                      else if (passing.flags.contains('flag_red'))
                        flagColor = SpeedDataTheme.flagRed;
                      else if (passing.flags.contains('flag_checkered'))
                        flagColor = Colors.white;

                      return Container(
                        color: flagColor.withOpacity(0.2),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        child: Row(
                          children: [
                            SizedBox(
                                width: 80,
                                child: Text(timeStr,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontFamily: 'monospace',
                                        fontSize: 12))),
                            Expanded(
                              child: Text(
                                passing.driverName,
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: flagColor == Colors.white
                                        ? Colors.white
                                        : flagColor,
                                    fontSize: 12),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    final lapTimeStr = _formatDuration(passing.lapTime);
                    final sectorTimeStr = _formatDuration(passing.sectorTime);

                    final participantId = passing.participantUid.toUpperCase();
                    final flagsLower =
                        passing.flags.map((flag) => flag.toLowerCase()).toSet();
                    final bool isDeleted = flagsLower.contains('deleted');
                    final bool isInvalid = flagsLower.contains('invalid');
                    final bool isBestLapFlag = flagsLower.contains('best_lap');
                    final bool isComputedBestLap = passing.lapTime != null &&
                        bestLapTimeByParticipant[passing.participantUid] !=
                            null &&
                        (passing.lapTime! -
                                    bestLapTimeByParticipant[
                                        passing.participantUid]!)
                                .abs() <
                            0.5;
                    final bool isBestLap = isBestLapFlag || isComputedBestLap;
                    final bool isPersonalBest =
                        flagsLower.contains('personal_best');
                    final bool isManualEntry = flagsLower.contains('manual') ||
                        participantId == 'MANUAL';
                    final bool isPhotocellPassing =
                        flagsLower.contains('photocell') ||
                            flagsLower.contains('photo_cell') ||
                            flagsLower.contains('photo') ||
                            participantId.contains('PHOTO');

                    final int minLapMilliseconds =
                        (widget.session?.minLapTimeSeconds ?? 0) * 1000;
                    final bool hasMinLapViolation = minLapMilliseconds > 0 &&
                        passing.lapTime != null &&
                        passing.lapTime! < minLapMilliseconds;

                    Color rowBackgroundColor = Colors.transparent;
                    if (isDeleted) {
                      rowBackgroundColor = Colors.grey.shade900;
                    } else if (isInvalid) {
                      rowBackgroundColor =
                          SpeedDataTheme.flagRed.withOpacity(0.1);
                    } else if (isBestLap) {
                      rowBackgroundColor =
                          SpeedDataTheme.flagBlue.withOpacity(0.25);
                    } else if (isPersonalBest) {
                      rowBackgroundColor =
                          SpeedDataTheme.flagGreen.withOpacity(0.3);
                    }

                    Color nameColor = SpeedDataTheme.textPrimary;
                    Color timeColor = SpeedDataTheme.textPrimary;
                    Color lapTimeColor = SpeedDataTheme.textPrimary;
                    Color sectorColor = SpeedDataTheme.textSecondary;

                    if (isDeleted || isInvalid) {
                      nameColor = SpeedDataTheme.flagRed;
                      timeColor = SpeedDataTheme.flagRed;
                      lapTimeColor = SpeedDataTheme.flagRed;
                      sectorColor = SpeedDataTheme.flagRed;
                    } else if (hasMinLapViolation) {
                      timeColor = SpeedDataTheme.flagRed;
                      lapTimeColor = SpeedDataTheme.flagRed;
                    }

                    if (isBestLap) {
                      timeColor = SpeedDataTheme.flagBlue;
                      lapTimeColor = SpeedDataTheme.flagBlue;
                    } else if (isPersonalBest) {
                      timeColor = SpeedDataTheme.flagGreen;
                      lapTimeColor = SpeedDataTheme.flagGreen;
                    }

                    IconData? statusIconData;
                    Color statusIconColor = SpeedDataTheme.textSecondary;
                    String? statusTooltip;

                    if (isDeleted) {
                      statusIconData = Icons.close;
                      statusIconColor = SpeedDataTheme.flagRed;
                      statusTooltip = 'Passagem deletada';
                    } else if (isInvalid) {
                      statusIconData = Icons.do_not_disturb_alt;
                      statusIconColor = SpeedDataTheme.flagRed;
                      statusTooltip = 'Volta invalidada';
                    } else if (isManualEntry) {
                      statusIconData = Icons.access_time;
                      statusIconColor = SpeedDataTheme.flagGreen;
                      statusTooltip = 'Entrada manual';
                    } else if (isPhotocellPassing) {
                      statusIconData = Icons.lightbulb;
                      statusIconColor = SpeedDataTheme.flagBlue;
                      statusTooltip = 'Fotocélula';
                    }

                    final Widget statusIconWidget = statusIconData != null
                        ? Tooltip(
                            message: statusTooltip ?? '',
                            child: Icon(statusIconData,
                                size: 16, color: statusIconColor),
                          )
                        : const SizedBox(width: 18);

                    return GestureDetector(
                      onSecondaryTapUp: (details) async {
                        final result = await showMenu(
                          context: context,
                          position: RelativeRect.fromLTRB(
                            details.globalPosition.dx,
                            details.globalPosition.dy,
                            details.globalPosition.dx,
                            details.globalPosition.dy,
                          ),
                          items: [
                            if (passing.flags.contains('invalid'))
                              const PopupMenuItem(
                                  value: 'validate',
                                  child: Text('Revalidate Passing'))
                            else
                              const PopupMenuItem(
                                  value: 'invalidate',
                                  child: Text('Invalidate Passing')),
                            if (passing.flags.contains('deleted'))
                              const PopupMenuItem(
                                  value: 'restore',
                                  child: Text('Restore Passing'))
                            else
                              const PopupMenuItem(
                                  value: 'delete',
                                  child: Text('Delete Passing')),
                          ],
                        );

                        if (result != null) {
                          final service = FirestoreService();
                          if (result == 'invalidate') {
                            await service.updatePassingFlag(
                                widget.raceId, passing.id, 'invalid', true);
                          } else if (result == 'validate') {
                            await service.updatePassingFlag(
                                widget.raceId, passing.id, 'invalid', false);
                          } else if (result == 'delete') {
                            await service.updatePassingFlag(
                                widget.raceId, passing.id, 'deleted', true);
                          } else if (result == 'restore') {
                            await service.updatePassingFlag(
                                widget.raceId, passing.id, 'deleted', false);
                          }
                        }
                      },
                      child: Container(
                        color: rowBackgroundColor,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        child: Row(
                          children: [
                            SizedBox(
                                width: 80,
                                child: Text(timeStr,
                                    style: TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 12,
                                        color: timeColor,
                                        decoration:
                                            passing.flags.contains('deleted')
                                                ? TextDecoration.lineThrough
                                                : null))),
                            SizedBox(
                                width: 50,
                                child: Text('',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12))), // Car number removed
                            Expanded(
                                child: Text(_resolveCompetitorName(passing),
                                    style: TextStyle(
                                        fontSize: 12, color: nameColor))),
                            SizedBox(
                                width: 40,
                                child: Text(
                                    calculatedLapNumbers[index].toString(),
                                    style: const TextStyle(fontSize: 12))),
                            SizedBox(
                                width: 80,
                                child: Text(lapTimeStr,
                                    style: TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 12,
                                        color: lapTimeColor,
                                        fontWeight: passing.lapTime != null
                                            ? FontWeight.bold
                                            : FontWeight.normal))),
                            SizedBox(
                                width: 80,
                                child: Text(sectorTimeStr,
                                    style: TextStyle(
                                        fontSize: 11, color: sectorColor))),
                            SizedBox(
                                width: 30,
                                child: Center(child: statusIconWidget)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
