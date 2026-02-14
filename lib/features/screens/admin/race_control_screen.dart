
import 'package:flutter/material.dart';
import 'package:speed_data/features/models/event_model.dart';
import 'package:speed_data/features/models/race_session_model.dart';
import 'package:speed_data/features/models/race_group_model.dart';
import 'package:speed_data/features/services/firestore_service.dart';
import 'package:speed_data/features/screens/admin/admin_map_view.dart'; 
import 'package:speed_data/features/screens/admin/widgets/passings_panel.dart';
import 'package:speed_data/features/screens/admin/widgets/leaderboard_panel.dart';
import 'package:speed_data/features/screens/admin/widgets/control_flags.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:speed_data/theme/speed_data_theme.dart';
import 'package:flutter/services.dart';

class RaceControlScreen extends StatefulWidget {
  final RaceEvent event;

  const RaceControlScreen({Key? key, required this.event}) : super(key: key);

  @override
  State<RaceControlScreen> createState() => _RaceControlScreenState();
}

class _RaceControlScreenState extends State<RaceControlScreen> with SingleTickerProviderStateMixin {
  final FirestoreService _firestoreService = FirestoreService();
  late TabController _tabController;
  RaceSession? _activeSession;
  String? _selectedSessionId;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _startSession(RaceSession session, RaceEvent currentEvent) async {
    final updatedSession = session.copyWith(status: SessionStatus.active);
     _updateSessionStatus(updatedSession, currentEvent);
  }

  void _finishSession(RaceSession session, RaceEvent currentEvent) async {
     final updatedSession = session.copyWith(status: SessionStatus.finished);
    _updateSessionStatus(updatedSession, currentEvent);
  }

   Future<void> _updateSessionStatus(RaceSession updatedSession, RaceEvent currentEvent) async {
    // Find the session index
    final index = currentEvent.sessions.indexWhere((s) => s.id == updatedSession.id);
    if (index != -1) {
      final updatedSessions = List<RaceSession>.from(currentEvent.sessions);
      updatedSessions[index] = updatedSession;

      final updatedEvent = currentEvent.copyWith(sessions: updatedSessions);

      await _firestoreService.updateEvent(updatedEvent);
    }
  }

  void _updateFlag(RaceFlag flag) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Flag ${flag.name} selected')));
    // TODO: Implement actual flag update in Firestore/Session
  }


  @override
  Widget build(BuildContext context) {
    return StreamBuilder<RaceEvent>(
      stream: _firestoreService.getEventStream(widget.event.id),
      builder: (context, snapshot) {
         if (!snapshot.hasData) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
         }
         
         final event = snapshot.data!;
         
         // 1. Determine "Active" session (running or next scheduled)
         RaceSession? defaultActiveSession;
         if (event.sessions.isNotEmpty) {
           defaultActiveSession = event.sessions.firstWhere(
             (s) => s.status == SessionStatus.active, 
             orElse: () => event.sessions.firstWhere(
               (s) => s.status == SessionStatus.scheduled, 
               orElse: () => event.sessions.last
             )
           );
         }

         // 2. Determine "Selected" session (user override)
         // If user selected a session, use it. Otherwise use default active.
         RaceSession? displaySession = defaultActiveSession;
         if (_selectedSessionId != null) {
            try {
              displaySession = event.sessions.firstWhere((s) => s.id == _selectedSessionId);
            } catch (e) {
              // Selected session might have been deleted
              _selectedSessionId = null;
            }
         }


        return KeyboardListener(
          focusNode: FocusNode(), 
          autofocus: true,
          onKeyEvent: (event) {
             if (event is KeyDownEvent) {
               if (event.logicalKey == LogicalKeyboardKey.f5) {
                  _updateFlag(RaceFlag.green);
               } else if (event.logicalKey == LogicalKeyboardKey.f6) {
                  _updateFlag(RaceFlag.yellow);
               } else if (event.logicalKey == LogicalKeyboardKey.f7) {
                  _updateFlag(RaceFlag.red);
                } else if (event.logicalKey == LogicalKeyboardKey.f8) {
                   _updateFlag(RaceFlag.checkered);
                } else if (event.logicalKey == LogicalKeyboardKey.f10) {
                   ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Manual Passing Entry (F10)')));
               }
             }
          },
          child: Scaffold(
          appBar: AppBar(
            title: Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(event.name, style: const TextStyle(fontSize: 14, color: SpeedDataTheme.textSecondary)),
                    if (displaySession != null)
                      Text(
                        event.groups.firstWhere((g) => g.id == displaySession!.groupId, orElse: () => RaceGroup(id: '', name: 'Unknown')).name,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                  ],
                ),
                const SizedBox(width: 20),
                if (displaySession != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: _getStatusColor(displaySession.status).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: _getStatusColor(displaySession.status)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${displaySession.name.isNotEmpty ? displaySession.name : displaySession.type.name.toUpperCase()} (${displaySession.status.name.toUpperCase()})',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        if (_selectedSessionId != null) ...[
                          const SizedBox(width: 8),
                          InkWell(
                            onTap: () => setState(() => _selectedSessionId = null),
                            child: const Icon(Icons.close, size: 16, color: SpeedDataTheme.textSecondary),
                          )
                        ]
                      ],
                    ),
                  ),
              ],
            ),
            actions: [
              IconButton(onPressed: () {}, icon: const Icon(Icons.settings), tooltip: 'Settings'),
              const SizedBox(width: 10),
              ElevatedButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back),
                label: const Text('Back to Groups'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: SpeedDataTheme.bgSurface,
                  foregroundColor: SpeedDataTheme.textPrimary,
                ),
              ),
              const SizedBox(width: 16),
            ],
            backgroundColor: SpeedDataTheme.bgBase,
          ),
          body: Column(
            children: [
              // Top Control Bar (Flags & Status)
              Container(
                padding: const EdgeInsets.all(8),
                color: SpeedDataTheme.bgSurface,
                child: Row(
                  children: [
                    // Action Buttons
                    Wrap(
                      spacing: 8,
                      children: [
                        _buildActionButton('START', Icons.play_arrow, SpeedDataTheme.flagGreen, () => _updateFlag(RaceFlag.green)),
                        _buildActionButton('SC', Icons.warning_amber, SpeedDataTheme.flagYellow, () => _updateFlag(RaceFlag.yellow)),
                        _buildActionButton('RED', Icons.block, SpeedDataTheme.flagRed, () => _updateFlag(RaceFlag.red)),
                        _buildActionButton('FINISH', Icons.flag, Colors.white, () => _updateFlag(RaceFlag.checkered), textColor: Colors.black),
                        const SizedBox(width: 16),
                        _buildActionButton('STOP', Icons.stop, Colors.grey.shade800, () {}, isOutlined: true),
                      ],
                    ),
                    const SizedBox(width: 24),
                    if (displaySession != null)
                      Row(
                        children: [
                          _buildInfoItem('Duration', '${displaySession.durationMinutes} min'),
                          const SizedBox(width: 16),
                          _buildInfoItem('Laps', '${displaySession.totalLaps ?? "-"}'),
                          const SizedBox(width: 16),
                          _buildInfoItem('Start', displaySession.startMethod),
                        ],
                      ),
                    const Spacer(),
                    // Session Timer Placeholder
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                         color: Colors.black,
                         borderRadius: BorderRadius.circular(4),
                         border: Border.all(color: SpeedDataTheme.textSecondary)
                      ),
                      child: const Text('00:00:00', style: TextStyle(fontFamily: 'monospace', fontSize: 24, color: SpeedDataTheme.flagGreen)),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: SpeedDataTheme.borderColor),
              // Main Content Area (3 Panes)
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Pane 1: Passings (Left)
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            color: SpeedDataTheme.bgSurface,
                            child: const Text('Passings', style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                          Expanded(
                            child: PassingsPanel(
                              raceId: event.trackId,
                              sessionType: displaySession?.type ?? SessionType.practice,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const VerticalDivider(width: 1, color: SpeedDataTheme.borderColor),
                    // Pane 2: Results (Middle)
                    Expanded(
                      flex: 4,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                           Container(
                            padding: const EdgeInsets.all(8),
                            color: SpeedDataTheme.bgSurface,
                            child: const Text('Results', style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                          Expanded(
                            child: LeaderboardPanel(
                               raceId: event.trackId,
                               checkpoints: [], // TODO: Pass actual checkpoints
                               sessionType: displaySession?.type ?? SessionType.race,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const VerticalDivider(width: 1, color: SpeedDataTheme.borderColor),
                    // Pane 3: Visualizations (Right) - Track Chart & Sessions List
                    Expanded(
                      flex: 3,
                      child: Column(
                        children: [
                          // Track Chart
                          Expanded(
                             flex: 2,
                             child: Stack(
                               children: [
                                 AdminMapView(
                                   raceId: event.trackId, 
                                   raceName: event.name,
                                   sessionType: displaySession?.type ?? SessionType.practice,
                                 ),
                                  const Positioned(
                                    top: 8, left: 8,
                                    child: Card(child: Padding(padding: EdgeInsets.all(4.0), child: Text('Track Chart', style: TextStyle(fontSize: 10))))
                                  )
                               ],
                             ),
                          ),
                          const Divider(height: 1, color: SpeedDataTheme.borderColor),
                          // Sessions List (Bottom Right - traditionally helpful for quick switching)
                          Expanded(
                            flex: 1,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  color: SpeedDataTheme.bgSurface,
                                  child: const Text('Sessions (Click to Select)', style: TextStyle(fontWeight: FontWeight.bold)),
                                ),
                                Expanded(child: _buildSessionsList(event, displaySession?.id)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ));
      }
    );
  }

  Widget _buildSessionsList(RaceEvent event, String? currentSessionId) {
    if (event.sessions.isEmpty) {
      return const Center(child: Text('No sessions scheduled', style: TextStyle(color: SpeedDataTheme.textSecondary)));
    }

    // Sort by scheduled time
    final sortedSessions = List<RaceSession>.from(event.sessions)
      ..sort((a, b) => a.scheduledTime.compareTo(b.scheduledTime));

    return ListView.separated(
      itemCount: sortedSessions.length,
      separatorBuilder: (context, index) => const Divider(height: 1, color: SpeedDataTheme.borderSubtle),
      itemBuilder: (context, index) {
        final session = sortedSessions[index];
        final isSelected = session.id == currentSessionId;
        final statusColor = _getStatusColor(session.status);
        final timeString = '${session.scheduledTime.hour.toString().padLeft(2, '0')}:${session.scheduledTime.minute.toString().padLeft(2, '0')}';


        return InkWell(
          onTap: () {
            setState(() {
              _selectedSessionId = session.id;
            });
          },
          child: Container(
            color: isSelected ? SpeedDataTheme.accentPrimary.withOpacity(0.1) : null,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Container(
                  width: 8, height: 8,
                  decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Text(timeString, style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: SpeedDataTheme.textSecondary)),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${session.type.name.toUpperCase()} ${session.name.isNotEmpty ? "- ${session.name}" : ""}', 
                        style: TextStyle(
                            fontWeight: FontWeight.bold, 
                            color: isSelected ? SpeedDataTheme.accentPrimary : SpeedDataTheme.textPrimary,
                            fontSize: 12
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(session.status.name.toUpperCase(), style: const TextStyle(color: SpeedDataTheme.textSecondary, fontSize: 10)),
                    ],
                  ),
                ),
                if (isSelected)
                  const Icon(Icons.check, size: 16, color: SpeedDataTheme.accentPrimary)
              ],
            ),
          ),
        );
      },
    );
  }

  Color _getStatusColor(SessionStatus status) {
    switch (status) {
      case SessionStatus.scheduled: return SpeedDataTheme.textSecondary;
      case SessionStatus.active: return SpeedDataTheme.flagGreen;
      case SessionStatus.finished: return SpeedDataTheme.textDisabled;
      default: return SpeedDataTheme.textSecondary;
    }
  }

  Widget _buildInfoItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label.toUpperCase(), style: const TextStyle(color: SpeedDataTheme.textSecondary, fontSize: 10, fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
      ],
    );
  }

  Widget _buildActionButton(String label, IconData icon, Color color, VoidCallback onPressed, {Color textColor = Colors.white, bool isOutlined = false}) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, color: textColor, size: 18),
      label: Text(label, style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
      style: ElevatedButton.styleFrom(
        backgroundColor: isOutlined ? Colors.transparent : color,
        foregroundColor: textColor,
        side: isOutlined ? BorderSide(color: color) : null,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
    );
  }
}
