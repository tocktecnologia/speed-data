
import 'package:flutter/material.dart';
import 'package:speed_data/features/models/race_session_model.dart';
import 'package:intl/intl.dart';
import 'package:speed_data/theme/speed_data_theme.dart';
import 'package:speed_data/features/services/firestore_service.dart';
import 'package:speed_data/features/models/passing_model.dart';

class PassingsPanel extends StatefulWidget {
  final String raceId;
  final String? sessionId;
  final SessionType sessionType;
  final RaceSession? session; // Added for time-based filtering

  const PassingsPanel({
    Key? key,
    required this.raceId,
    this.sessionId,
    required this.sessionType,
    this.session,
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
    final event = await FirestoreService().getActiveEventForTrack(widget.raceId);
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
              final fullName = '${competitor.firstName} ${competitor.lastName}'.trim();
              _competitorNameCache[competitor.uid] = fullName.isNotEmpty ? fullName : 'Unknown';
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

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<PassingModel>>(
      stream: FirestoreService().getPassingsStream(widget.raceId, sessionId: widget.sessionId, session: widget.session),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          debugPrint('PassingsPanel Error: ${snapshot.error}');
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, color: SpeedDataTheme.flagRed, size: 32),
                  const SizedBox(height: 8),
                  Text('Error loading passings: ${snapshot.error}', 
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: SpeedDataTheme.textSecondary, fontSize: 12)),
                ],
              ),
            ),
          );
        }
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

        final passings = snapshot.data!;
        
        // Calculate lap numbers dynamically: track lap number for each passing
        final Map<String, int> currentLapPerCompetitor = {};
        final List<int> calculatedLapNumbers = [];
        
        for (int i = 0; i < passings.length; i++) {
          final passing = passings[i];
          if (passing.participantUid == 'SYSTEM') {
            calculatedLapNumbers.add(0); // System messages don't have lap numbers
          } else {
            // Increment lap count for this competitor
            currentLapPerCompetitor[passing.participantUid] = 
                (currentLapPerCompetitor[passing.participantUid] ?? 0) + 1;
            calculatedLapNumbers.add(currentLapPerCompetitor[passing.participantUid]!);
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
                     SizedBox(width: 80, child: Text('TIME', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                     SizedBox(width: 50, child: Text('#', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                     Expanded(child: Text('NAME', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                     SizedBox(width: 40, child: Text('LAP', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                     SizedBox(width: 80, child: Text('LAP TIME', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                     SizedBox(width: 80, child: Text('SECTOR', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                     SizedBox(width: 30, child: Icon(Icons.battery_std, size: 14)),
                   ],
                 ),
               ),
               const Divider(height: 1, color: SpeedDataTheme.borderColor),
              Expanded(
                child: ListView.separated(
                  controller: _scrollController,
                  itemCount: passings.length,
                  separatorBuilder: (context, index) => const Divider(height: 1, color: SpeedDataTheme.borderSubtle),
                  itemBuilder: (context, index) {
                    final passing = passings[index];
                    final timeStr = DateFormat('HH:mm:ss.SSS').format(passing.timestamp);

                    // Check for System Flags
                    if (passing.participantUid == 'SYSTEM') {
                       Color flagColor = Colors.grey;
                       if (passing.flags.contains('flag_green')) flagColor = SpeedDataTheme.flagGreen;
                       else if (passing.flags.contains('flag_yellow')) flagColor = SpeedDataTheme.flagYellow;
                       else if (passing.flags.contains('flag_red')) flagColor = SpeedDataTheme.flagRed;
                       else if (passing.flags.contains('flag_checkered')) flagColor = Colors.white;

                       return Container(
                         color: flagColor.withOpacity(0.2),
                         padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                         child: Row(
                           children: [
                             SizedBox(width: 80, child: Text(timeStr, style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'monospace', fontSize: 12))),
                             Expanded(
                               child: Text(
                                 passing.driverName, 
                                 style: TextStyle(
                                   fontWeight: FontWeight.bold, 
                                   color: flagColor == Colors.white ? Colors.white : flagColor,
                                   fontSize: 12
                                  ),
                                  textAlign: TextAlign.center,
                               ),
                             ),
                           ],
                         ),
                       );
                    }
                    
                    // Formatting helper
                    String formatDuration(double? ms) {
                      if (ms == null) return '--:--:--';
                       final duration = Duration(milliseconds: ms.toInt());
                       final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
                       final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
                       final milliseconds = (duration.inMilliseconds.remainder(1000)).toString().padLeft(3, '0');
                       return '$minutes:$seconds.$milliseconds';
                    }

                    final lapTimeStr = formatDuration(passing.lapTime);
                    final sectorTimeStr = formatDuration(passing.sectorTime);

                    // Orbits-style Coloring
                    Color backgroundColor = Colors.transparent;
                    if (passing.flags.contains('best_lap')) {
                      backgroundColor = Colors.purple.withOpacity(0.3);
                    } else if (passing.flags.contains('personal_best')) {
                      backgroundColor = Colors.green.withOpacity(0.3);
                    } else if (passing.flags.contains('invalid')) {
                      backgroundColor = SpeedDataTheme.flagRed.withOpacity(0.1);
                    }

                    Color textColor = SpeedDataTheme.textPrimary;
                    if (passing.flags.contains('invalid')) {
                      textColor = SpeedDataTheme.flagRed;
                    }

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
                               const PopupMenuItem(value: 'validate', child: Text('Revalidate Passing'))
                            else
                               const PopupMenuItem(value: 'invalidate', child: Text('Invalidate Passing')),
                            
                             if (passing.flags.contains('deleted'))
                               const PopupMenuItem(value: 'restore', child: Text('Restore Passing'))
                            else
                               const PopupMenuItem(value: 'delete', child: Text('Delete Passing')),
                          ],
                        );

                        if (result != null) {
                          final service = FirestoreService();
                          if (result == 'invalidate') {
                             await service.updatePassingFlag(widget.raceId, passing.id, 'invalid', true);
                          } else if (result == 'validate') {
                             await service.updatePassingFlag(widget.raceId, passing.id, 'invalid', false);
                          } else if (result == 'delete') {
                             await service.updatePassingFlag(widget.raceId, passing.id, 'deleted', true);
                          } else if (result == 'restore') {
                             await service.updatePassingFlag(widget.raceId, passing.id, 'deleted', false);
                          }
                        }
                      },
                      child: Container(
                        color: backgroundColor,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        child: Row(
                          children: [
                            SizedBox(width: 80, child: Text(timeStr, style: TextStyle(fontFamily: 'monospace', fontSize: 12, decoration: passing.flags.contains('deleted') ? TextDecoration.lineThrough : null))),
                            SizedBox(width: 50, child: Text('', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12))), // Car number removed
                            Expanded(child: Text(_getCompetitorName(passing.participantUid), style: TextStyle(fontSize: 12, color: textColor))),
                            SizedBox(width: 40, child: Text(calculatedLapNumbers[index].toString(), style: const TextStyle(fontSize: 12))),
                            SizedBox(width: 80, child: Text(lapTimeStr, style: TextStyle(fontFamily: 'monospace', fontSize: 12, fontWeight: passing.lapTime != null ? FontWeight.bold : FontWeight.normal))),
                            SizedBox(width: 80, child: Text(sectorTimeStr, style: const TextStyle(fontSize: 11, color: SpeedDataTheme.textSecondary))),
                            const SizedBox(width: 30), // Placeholder for battery icon if needed
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
