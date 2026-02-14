
import 'package:flutter/material.dart';
import 'package:speed_data/features/models/event_model.dart';
import 'package:speed_data/features/models/race_group_model.dart';
import 'package:speed_data/features/models/race_session_model.dart';
import 'package:speed_data/features/models/competitor_model.dart';
import 'package:speed_data/features/services/firestore_service.dart';
import 'package:speed_data/features/screens/admin/create_event_screen.dart';
import 'package:speed_data/features/screens/admin/session_settings_screen.dart';
import 'package:speed_data/features/screens/admin/competitor_settings_screen.dart';
import 'package:speed_data/features/screens/admin/race_control_screen.dart';
import 'package:speed_data/theme/speed_data_theme.dart';
import 'package:uuid/uuid.dart';

class EventRegistrationScreen extends StatefulWidget {
  final RaceEvent event;

  const EventRegistrationScreen({Key? key, required this.event}) : super(key: key);

  @override
  State<EventRegistrationScreen> createState() => _EventRegistrationScreenState();
}

class _EventRegistrationScreenState extends State<EventRegistrationScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  final Uuid _uuid = const Uuid();
  RaceEvent? _currentEvent;
  String? _selectedGroupId;
  int _selectedTabIndex = 0; // 0: Schedule, 1: Competitors

  @override
  void initState() {
    super.initState();
    _currentEvent = widget.event;
    // Removed auto-selection to support mobile navigation flow
  }

  Future<void> _refreshEvent() async {
    if (_currentEvent == null) return;
    final updatedEvent = await _firestoreService.getEvent(_currentEvent!.id);
    if (updatedEvent != null) {
      setState(() {
        _currentEvent = updatedEvent;
      });
    }
  }

  Future<void> _saveEvent() async {
    if (_currentEvent != null) {
      await _firestoreService.updateEvent(_currentEvent!);
      setState(() {});
    }
  }

  // --- Group Logic ---
  void _addGroup() {
    final TextEditingController nameController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New Group / Category'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(labelText: 'Group Name (e.g. Kids, Pro)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              if (nameController.text.isNotEmpty) {
                final newGroup = RaceGroup(
                  id: _uuid.v4(),
                  name: nameController.text.trim(),
                );
                setState(() {
                  _currentEvent!.groups.add(newGroup);
                  _selectedGroupId = newGroup.id;
                });
                _saveEvent();
                Navigator.pop(context);
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  // --- Session Logic ---
  void _addSession(RaceGroup group) {
     // Dialog to add session to group
     // ... implementation similar to before but linked to group
  }

  @override
  Widget build(BuildContext context) {
    if (_currentEvent == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 700;
        final showDetails = _selectedGroupId != null;

        return Scaffold(
          appBar: AppBar(
            title: Text(isMobile && showDetails 
                ? _currentEvent!.groups.firstWhere((g) => g.id == _selectedGroupId).name 
                : 'Manage Groups: ${_currentEvent!.name}'),
            backgroundColor: Colors.black,
          actions: [
            IconButton(
              icon: const Icon(Icons.sports_score, color: SpeedDataTheme.accentPrimary), // Flag icon
              tooltip: 'Race Control',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => RaceControlScreen(event: _currentEvent!)),
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.settings),
              tooltip: 'Edit Event Details',
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => CreateEventScreen(event: _currentEvent),
                  ),
                );
                _refreshEvent();
              },
            ),
          ],
          leading: isMobile && showDetails
                ? IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () {
                      setState(() {
                        _selectedGroupId = null;
                      });
                    },
                  )
                : null, // Default
          ),
          body: isMobile
              ? _buildMobileLayout(showDetails)
              : _buildDesktopLayout(),
          floatingActionButton: (!showDetails || !isMobile) ? FloatingActionButton.extended(
            onPressed: _addGroup,
            label: const Text('Add Group'),
            icon: const Icon(Icons.add),
            backgroundColor: Colors.blue,
          ) : null,
        );
      },
    );
  }

  Widget _buildMobileLayout(bool showDetails) {
    if (showDetails) {
      return _buildGroupDetails(_currentEvent!.groups.firstWhere((g) => g.id == _selectedGroupId), isMobile: true);
    } else {
      return _buildGroupList();
    }
  }

  Widget _buildDesktopLayout() {
    return Row(
      children: [
        // sidebar: Groups
        Container(
          width: 250,
          color: SpeedDataTheme.bgSurface,
          child: Column(
            children: [
              Container(
                 padding: const EdgeInsets.all(12),
                 color: SpeedDataTheme.bgElevated,
                 width: double.infinity,
                 child: Center(child: Text('Groups', style: SpeedDataTheme.textTheme.headlineMedium)),
               ),
              Expanded(child: _buildGroupList()),
            ],
          ),
        ),
        // Main Content
        Expanded(
          child: _selectedGroupId == null
              ? const Center(child: Text('Select a Group to manage Sessions and Competitors'))
              : _buildGroupDetails(_currentEvent!.groups.firstWhere((g) => g.id == _selectedGroupId)),
        ),
      ],
    );
  }

  Widget _buildGroupList() {
    if (_currentEvent!.groups.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(20.0),
          child: Text('No groups yet.\nTap "Add Group" to start.', textAlign: TextAlign.center, style: TextStyle(color: SpeedDataTheme.textSecondary)),
        ),
      );
    }
    return ListView.builder(
      itemCount: _currentEvent!.groups.length,
      itemBuilder: (context, index) {
        final group = _currentEvent!.groups[index];
        final isSelected = group.id == _selectedGroupId;
        return ListTile(
          title: Text(group.name, style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.normal, color: isSelected ? Colors.white : SpeedDataTheme.textPrimary)),
          selected: isSelected,
          selectedTileColor: SpeedDataTheme.accentPrimary,
          onTap: () {
            setState(() {
              _selectedGroupId = group.id;
            });
          },
          trailing: IconButton(
            icon: const Icon(Icons.delete_outline, size: 20, color: SpeedDataTheme.textSecondary),
            onPressed: () => _confirmDeleteGroup(index),
          ),
        );
      },
    );
  }

  void _confirmDeleteGroup(int index) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Group?'),
        content: const Text('This will delete the group and all its sessions and competitors. This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              setState(() {
                final group = _currentEvent!.groups[index];
                _currentEvent!.groups.removeAt(index);
                if (_selectedGroupId == group.id) _selectedGroupId = null;
              });
              _saveEvent();
              Navigator.pop(context);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteCompetitor(Competitor comp) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Competitor?'),
        content: Text('Are you sure you want to delete ${comp.name}? This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              _firestoreService.removeCompetitor(_currentEvent!.id, comp.id);
              Navigator.pop(context);
            },
            style: TextButton.styleFrom(foregroundColor: SpeedDataTheme.flagRed),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteSession(RaceSession session) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Session?'),
        content: const Text('This will delete the session and its results. This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              setState(() {
                _currentEvent!.sessions.remove(session);
              });
              _saveEvent();
              Navigator.pop(context);
            },
            style: TextButton.styleFrom(foregroundColor: SpeedDataTheme.flagRed),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupDetails(RaceGroup group, {bool isMobile = false}) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          color: SpeedDataTheme.bgElevated,
          child: Row(
            children: [
              if (!isMobile)
                Text(group.name, style: SpeedDataTheme.textTheme.headlineMedium),
              const Spacer(),
              // Tabs at top of detail view (Orbits style)
               ToggleButtons(
                color: SpeedDataTheme.textSecondary,
                selectedColor: SpeedDataTheme.textPrimary,
                fillColor: SpeedDataTheme.accentPrimary,
                borderRadius: BorderRadius.circular(8),
                constraints: const BoxConstraints(minHeight: 36),
                isSelected: [_selectedTabIndex == 0, _selectedTabIndex == 1],
                onPressed: (index) {
                  setState(() {
                    _selectedTabIndex = index;
                  });
                },
                children: const [
                  Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('Running Order')), // Schedule
                  Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('Competitors')),
                ],
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _selectedTabIndex == 0 
            ? _buildScheduleView(group)
            : _buildCompetitorsView(group),
        ),
      ],
    );
  }

  // --- Views ---

  Widget _buildScheduleView(RaceGroup group) {
    final groupSessions = _currentEvent!.sessions.where((s) => s.groupId == group.id).toList();
    
    return Column(
      children: [
         Padding(
           padding: const EdgeInsets.all(8.0),
           child: ElevatedButton.icon(
             icon: const Icon(Icons.add),
             label: const Text('Add Session'),
             onPressed: () => _showAddSessionDialog(group),
           ),
         ),
        Expanded(
          child: ListView.builder(
            itemCount: groupSessions.length,
            itemBuilder: (context, index) {
              final session = groupSessions[index];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: ListTile(
                  leading: const Icon(Icons.timer_outlined), // Simplified icon
                  title: Text(session.name.isNotEmpty ? session.name : session.type.name.toUpperCase()),
                  subtitle: Text(session.status.name),
                  onTap: () => _editSession(session), // Tap to edit
                  trailing: IconButton(
                    icon: const Icon(Icons.delete, color: SpeedDataTheme.accentDanger), 
                    onPressed: () => _confirmDeleteSession(session)
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCompetitorsView(RaceGroup group) {
    // Competitors are sub-collection, so stream builder
    return StreamBuilder<List<Competitor>>(
      stream: _firestoreService.getCompetitorsStream(_currentEvent!.id),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        
        final competitors = snapshot.data!.where((c) => c.groupId == group.id).toList();

        return Column(
          children: [
             Padding(
               padding: const EdgeInsets.all(8.0),
               child: Row(
                 mainAxisAlignment: MainAxisAlignment.center,
                 children: [
                    ElevatedButton.icon(
                      icon: const Icon(Icons.person_add),
                      label: const Text('Add'),
                      onPressed: () => _showAddCompetitorDialog(group),
                    ),
                    const SizedBox(width: 16),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.swap_horiz, color: SpeedDataTheme.textPrimary),
                      label: const Text('Transfer', style: TextStyle(color: SpeedDataTheme.textPrimary)),
                      style: OutlinedButton.styleFrom(side: const BorderSide(color: SpeedDataTheme.textSecondary)),
                      onPressed: () => _showTransferCompetitorsDialog(group),
                    ),
                 ],
               ),
             ),
            Expanded(
              child: ListView.builder(
                itemCount: competitors.length,
                itemBuilder: (context, index) {
                  final comp = competitors[index];
                  return Card(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: ListTile(
                      leading: CircleAvatar(child: Text(comp.number)),
                      title: Text(comp.name),
                      subtitle: Text('Category: ${comp.category}'),
                      onTap: () => _editCompetitor(comp),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete, color: SpeedDataTheme.accentDanger),
                        onPressed: () => _confirmDeleteCompetitor(comp),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  // --- Dialogs ---

  void _showAddSessionDialog(RaceGroup group) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SessionSettingsScreen(
          session: RaceSession(
             id: _uuid.v4(),
             type: SessionType.practice,
             status: SessionStatus.scheduled,
             scheduledTime: DateTime.now(),
             groupId: group.id,
          ),
          onSave: (newSession) {
             setState(() {
                _currentEvent!.sessions.add(newSession);
             });
             _saveEvent();
          },
        ),
      ),
    );
  }
  
  void _editSession(RaceSession session) {
     Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SessionSettingsScreen(
          session: session,
          onSave: (updatedSession) {
             setState(() {
                final index = _currentEvent!.sessions.indexWhere((s) => s.id == updatedSession.id);
                if (index != -1) {
                  _currentEvent!.sessions[index] = updatedSession;
                }
             });
             _saveEvent();
          },
        ),
      ),
    );
  }

  void _showAddCompetitorDialog(RaceGroup group) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CompetitorSettingsScreen(
          groupId: group.id,
          onSave: (newComp) => _firestoreService.addCompetitor(_currentEvent!.id, newComp),
        ),
      ),
    );
  }

  void _showTransferCompetitorsDialog(RaceGroup currentGroup) async {
    final allCompetitors = await _firestoreService.getCompetitors(_currentEvent!.id);
    final groupCompetitors = allCompetitors.where((c) => c.groupId == currentGroup.id).toList();
    
    if (groupCompetitors.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No competitors in this group to transfer.')));
      return;
    }

    final otherGroups = _currentEvent!.groups.where((g) => g.id != currentGroup.id).toList();
    if (otherGroups.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No other groups to transfer to.')));
      return;
    }

    Set<String> selectedIds = Set<String>.from(groupCompetitors.map((c) => c.id));
    String? targetGroupId = otherGroups.first.id;
    bool isCopy = false; // Default to Move

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Transfer Competitors'),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Transferring from ${currentGroup.name}', style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      value: targetGroupId,
                      decoration: const InputDecoration(labelText: 'Target Group'),
                      items: otherGroups.map((g) => DropdownMenuItem(value: g.id, child: Text(g.name))).toList(),
                      onChanged: (val) => setState(() => targetGroupId = val),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                         const Text('Action: '),
                         Radio<bool>(value: false, groupValue: isCopy, onChanged: (v) => setState(() => isCopy = v!), activeColor: SpeedDataTheme.accentPrimary),
                         const Text('Move'),
                         Radio<bool>(value: true, groupValue: isCopy, onChanged: (v) => setState(() => isCopy = v!), activeColor: SpeedDataTheme.accentPrimary),
                         const Text('Copy'),
                      ],
                    ),
                    const SizedBox(height: 8),
                     Row(
                       mainAxisAlignment: MainAxisAlignment.end,
                       children: [
                         TextButton(onPressed: () => setState(() => selectedIds.addAll(groupCompetitors.map((c) => c.id))), child: const Text('Select All')),
                         TextButton(onPressed: () => setState(() => selectedIds.clear()), child: const Text('Select None')),
                       ],
                     ),
                    const Divider(),
                    Expanded(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: groupCompetitors.length,
                        itemBuilder: (context, index) {
                          final comp = groupCompetitors[index];
                          return CheckboxListTile(
                            title: Text(comp.name),
                            subtitle: Text('#${comp.number}'),
                            value: selectedIds.contains(comp.id),
                            activeColor: SpeedDataTheme.accentPrimary,
                            onChanged: (val) {
                              setState(() {
                                if (val == true) selectedIds.add(comp.id);
                                else selectedIds.remove(comp.id);
                              });
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                ElevatedButton(
                  onPressed: selectedIds.isEmpty || targetGroupId == null ? null : () {
                     Navigator.pop(context); // Close dialog
                     _performTransfer(groupCompetitors.where((c) => selectedIds.contains(c.id)).toList(), targetGroupId!, isCopy);
                  },
                  child: Text(isCopy ? 'Copy' : 'Move'),
                ),
              ],
            );
          }
        );
      },
    );
  }

  void _performTransfer(List<Competitor> competitors, String targetGroupId, bool isCopy) async {
      for (final comp in competitors) {
        if (isCopy) {
           final newComp = comp.copyWith(id: _uuid.v4(), groupId: targetGroupId);
           await _firestoreService.addCompetitor(_currentEvent!.id, newComp);
        } else {
           final updatedComp = comp.copyWith(groupId: targetGroupId);
           await _firestoreService.addCompetitor(_currentEvent!.id, updatedComp); 
        }
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Successfully ${isCopy ? 'copied' : 'moved'} ${competitors.length} competitors')));
  }
  
  void _editCompetitor(Competitor competitor) {
     Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CompetitorSettingsScreen(
          competitor: competitor,
          groupId: competitor.groupId,
          onSave: (updatedCompetitor) {
             _firestoreService.addCompetitor(_currentEvent!.id, updatedCompetitor);
          },
        ),
      ),
    );
  }
}
