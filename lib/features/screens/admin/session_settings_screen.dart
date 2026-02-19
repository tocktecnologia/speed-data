import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:speed_data/features/models/race_session_model.dart';

class SessionSettingsScreen extends StatefulWidget {
  final RaceSession? session;
  final Function(RaceSession) onSave;
  final List<Map<String, dynamic>> trackCheckpoints;

  const SessionSettingsScreen({
    Key? key,
    this.session,
    required this.onSave,
    this.trackCheckpoints = const [],
  }) : super(key: key);

  @override
  State<SessionSettingsScreen> createState() => _SessionSettingsScreenState();
}

class _SessionSettingsScreenState extends State<SessionSettingsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _formKey = GlobalKey<FormState>();

  // General
  final _nameController = TextEditingController();
  final _shortNameController = TextEditingController();
  DateTime _date = DateTime.now();
  TimeOfDay _time = TimeOfDay.now();
  SessionType _type = SessionType.practice;

  // Timing
  String _startMethod = 'First Passing';
  bool _startOnFirstPassing = true;
  int _minLapTime = 0;
  bool _redFlagStopsClock = true;
  bool _redFlagDeletesPassings = false;

  // Auto Finish
  String _finishMode = 'Time';
  int _durationMinutes = 15;
  int _laps = 10;

  // Qualify
  String _qualCriteria = 'None';
  double _qualValue = 0;

  // Timelines
  List<SessionTimeline> _timelines = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);

    if (widget.session != null) {
      final session = widget.session!;
      _nameController.text = session.name;
      _shortNameController.text = session.shortName;
      _date = session.scheduledTime;
      _time = TimeOfDay.fromDateTime(session.scheduledTime);
      _type = session.type;

      _startMethod = session.startMethod;
      _startOnFirstPassing = session.startOnFirstPassing;
      _minLapTime = session.minLapTimeSeconds;
      _redFlagStopsClock = session.redFlagStopsClock;
      _redFlagDeletesPassings = session.redFlagDeletesPassings;

      _finishMode = session.finishMode;
      _durationMinutes = session.durationMinutes;
      _laps = session.totalLaps ?? 0;

      _qualCriteria = session.qualificationCriteria;
      _qualValue = session.qualificationValue ?? 0;
      _timelines = List<SessionTimeline>.from(session.timelines)
        ..sort((a, b) => a.order.compareTo(b.order));
    }

    if (_timelines.isEmpty) {
      _timelines = _buildInitialTimelinesFromTrackCheckpoints();
    } else {
      _normalizeTimelineOrder();
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _nameController.dispose();
    _shortNameController.dispose();
    super.dispose();
  }

  SessionTimeline _createDefaultStartFinish() {
    return SessionTimeline(
      id: _nextTimelineId(),
      type: SessionTimelineType.startFinish,
      name: 'Start/Finish',
      order: 0,
      checkpointIndex: 0,
      enabled: true,
    );
  }

  List<SessionTimeline> _buildInitialTimelinesFromTrackCheckpoints() {
    final checkpoints = widget.trackCheckpoints;
    if (checkpoints.length < 2) {
      return [_createDefaultStartFinish()];
    }

    final List<SessionTimeline> initial = [];
    final int seed = DateTime.now().microsecondsSinceEpoch;
    int order = 0;

    initial.add(
      SessionTimeline(
        id: 'timeline_${seed}_$order',
        type: SessionTimelineType.startFinish,
        name: 'Start/Finish',
        order: order,
        checkpointIndex: 0,
        enabled: true,
      ),
    );
    order++;

    // Track checkpoints usually close the loop by repeating the first point at
    // the end. In both closed and open tracks, intermediates are 1..(last-1).
    final int lastIndex = checkpoints.length - 1;
    for (int checkpointIndex = 1;
        checkpointIndex < lastIndex;
        checkpointIndex++) {
      initial.add(
        SessionTimeline(
          id: 'timeline_${seed}_$order',
          type: SessionTimelineType.split,
          name: 'Split $order',
          order: order,
          checkpointIndex: checkpointIndex,
          enabled: true,
        ),
      );
      order++;
    }

    return initial;
  }

  String _nextTimelineId() {
    return 'timeline_${DateTime.now().microsecondsSinceEpoch}_${_timelines.length}';
  }

  String _timelineTypeLabel(SessionTimelineType type) {
    switch (type) {
      case SessionTimelineType.startFinish:
        return 'Start/Finish';
      case SessionTimelineType.split:
        return 'Split';
      case SessionTimelineType.trap:
        return 'Trap';
    }
  }

  String _defaultTimelineName(SessionTimelineType type, {int? editingIndex}) {
    if (type == SessionTimelineType.startFinish) return 'Start/Finish';

    int count = 0;
    for (int i = 0; i < _timelines.length; i++) {
      if (editingIndex != null && i == editingIndex) continue;
      if (_timelines[i].type == type) count++;
    }
    final next = count + 1;
    if (type == SessionTimelineType.split) return 'Split $next';
    return 'Trap $next';
  }

  void _normalizeTimelineOrder() {
    _timelines = _timelines
        .asMap()
        .entries
        .map((entry) => entry.value.copyWith(order: entry.key))
        .toList(growable: true);
  }

  void _reorderTimelines(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) {
        newIndex -= 1;
      }
      final moved = _timelines.removeAt(oldIndex);
      _timelines.insert(newIndex, moved);
      _normalizeTimelineOrder();
    });
  }

  Future<void> _showTimelineEditor({int? index}) async {
    final editing = index != null ? _timelines[index] : null;
    SessionTimelineType selectedType = editing?.type ??
        (_timelines.any(
                (timeline) => timeline.type == SessionTimelineType.startFinish)
            ? SessionTimelineType.split
            : SessionTimelineType.startFinish);
    bool enabled = editing?.enabled ?? true;
    final nameController = TextEditingController(
      text: editing?.name ??
          _defaultTimelineName(selectedType, editingIndex: index),
    );
    final checkpointController = TextEditingController(
      text: (editing?.checkpointIndex ?? 0).toString(),
    );

    final saved = await showDialog<SessionTimeline>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text(editing == null ? 'Add Timeline' : 'Edit Timeline'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<SessionTimelineType>(
                    initialValue: selectedType,
                    decoration: const InputDecoration(labelText: 'Type'),
                    items: SessionTimelineType.values
                        .map((type) => DropdownMenuItem(
                              value: type,
                              child: Text(_timelineTypeLabel(type)),
                            ))
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      setDialogState(() {
                        selectedType = value;
                        if (nameController.text.trim().isEmpty) {
                          nameController.text = _defaultTimelineName(
                            selectedType,
                            editingIndex: index,
                          );
                        }
                      });
                    },
                  ),
                  TextFormField(
                    controller: nameController,
                    decoration:
                        const InputDecoration(labelText: 'Name (optional)'),
                  ),
                  TextFormField(
                    controller: checkpointController,
                    decoration: const InputDecoration(
                      labelText: 'Checkpoint Index',
                      helperText: '0 = start line, 1..N = intermediates',
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Enabled'),
                    value: enabled,
                    onChanged: (value) => setDialogState(() => enabled = value),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  final parsedCheckpoint = int.tryParse(
                        checkpointController.text.trim(),
                      ) ??
                      0;
                  final checkpointIndex =
                      parsedCheckpoint < 0 ? 0 : parsedCheckpoint;
                  final resolvedName = nameController.text.trim().isNotEmpty
                      ? nameController.text.trim()
                      : _defaultTimelineName(
                          selectedType,
                          editingIndex: index,
                        );
                  Navigator.pop(
                    context,
                    SessionTimeline(
                      id: editing?.id ?? _nextTimelineId(),
                      type: selectedType,
                      name: resolvedName,
                      order: editing?.order ?? _timelines.length,
                      checkpointIndex: checkpointIndex,
                      enabled: enabled,
                    ),
                  );
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );

    nameController.dispose();
    checkpointController.dispose();
    if (saved == null) return;

    setState(() {
      if (index != null) {
        _timelines[index] = saved;
      } else {
        _timelines.add(saved);
      }
      _normalizeTimelineOrder();
    });
  }

  Future<void> _deleteTimeline(int index) async {
    final timeline = _timelines[index];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Timeline'),
        content: Text('Remove "${timeline.name}" from this session?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    setState(() {
      _timelines.removeAt(index);
      _normalizeTimelineOrder();
    });
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;

    final hasStartFinish = _timelines.any(
      (timeline) =>
          timeline.enabled && timeline.type == SessionTimelineType.startFinish,
    );
    if (!hasStartFinish) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'At least one enabled Start/Finish timeline is required.',
          ),
        ),
      );
      _tabController.animateTo(4);
      return;
    }

    final scheduledTime = DateTime(
      _date.year,
      _date.month,
      _date.day,
      _time.hour,
      _time.minute,
    );

    final normalizedTimelines = _timelines
        .asMap()
        .entries
        .map((entry) => entry.value.copyWith(order: entry.key))
        .toList(growable: false);

    final newSession = RaceSession(
      id: widget.session?.id ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      type: _type,
      status: widget.session?.status ?? SessionStatus.scheduled,
      scheduledTime: scheduledTime,
      durationMinutes: _durationMinutes,
      totalLaps: _laps,
      groupId: widget.session?.groupId ?? '',
      name: _nameController.text,
      shortName: _shortNameController.text,
      startMethod: _startMethod,
      startOnFirstPassing: _startOnFirstPassing,
      minLapTimeSeconds: _minLapTime,
      redFlagStopsClock: _redFlagStopsClock,
      redFlagDeletesPassings: _redFlagDeletesPassings,
      finishMode: _finishMode,
      qualificationCriteria: _qualCriteria,
      qualificationValue: _qualValue,
      actualStartTime: widget.session?.actualStartTime,
      actualEndTime: widget.session?.actualEndTime,
      timelines: normalizedTimelines,
    );

    widget.onSave(newSession);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Session Settings'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const [
            Tab(text: 'General'),
            Tab(text: 'Timing'),
            Tab(text: 'Auto Finish'),
            Tab(text: 'Qualification'),
            Tab(text: 'Timelines'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            onPressed: _save,
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: TabBarView(
          controller: _tabController,
          children: [
            _buildGeneralTab(),
            _buildTimingTab(),
            _buildAutoFinishTab(),
            _buildQualificationTab(),
            _buildTimelinesTab(),
          ],
        ),
      ),
    );
  }

  Widget _buildGeneralTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextFormField(
          controller: _nameController,
          decoration: const InputDecoration(
            labelText: 'Name (e.g. Practice 1)',
          ),
        ),
        TextFormField(
          controller: _shortNameController,
          decoration: const InputDecoration(labelText: 'Short Name'),
        ),
        ListTile(
          title: Text('Date: ${DateFormat('yyyy-MM-dd').format(_date)}'),
          trailing: const Icon(Icons.calendar_today),
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: _date,
              firstDate: DateTime(2020),
              lastDate: DateTime(2030),
            );
            if (picked != null) {
              setState(() => _date = picked);
            }
          },
        ),
        ListTile(
          title: Text('Time: ${_time.format(context)}'),
          trailing: const Icon(Icons.access_time),
          onTap: () async {
            final picked = await showTimePicker(
              context: context,
              initialTime: _time,
            );
            if (picked != null) {
              setState(() => _time = picked);
            }
          },
        ),
        DropdownButtonFormField<SessionType>(
          initialValue: _type,
          decoration: const InputDecoration(labelText: 'Type'),
          items: SessionType.values
              .map((type) => DropdownMenuItem(
                    value: type,
                    child: Text(type.name.toUpperCase()),
                  ))
              .toList(),
          onChanged: (value) {
            if (value != null) {
              setState(() => _type = value);
            }
          },
        ),
      ],
    );
  }

  Widget _buildTimingTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        DropdownButtonFormField<String>(
          initialValue: _startMethod,
          decoration: const InputDecoration(labelText: 'Start Method'),
          items: ['First Passing', 'Flag', 'Staggered']
              .map(
                  (value) => DropdownMenuItem(value: value, child: Text(value)))
              .toList(),
          onChanged: (value) {
            if (value != null) {
              setState(() => _startMethod = value);
            }
          },
        ),
        SwitchListTile(
          title: const Text('Start on First Passing'),
          value: _startOnFirstPassing,
          onChanged: (value) => setState(() => _startOnFirstPassing = value),
        ),
        TextFormField(
          initialValue: _minLapTime.toString(),
          decoration: const InputDecoration(
            labelText: 'Minimum Lap Time (sec)',
          ),
          keyboardType: TextInputType.number,
          onChanged: (value) => _minLapTime = int.tryParse(value) ?? 0,
        ),
        SwitchListTile(
          title: const Text('Red Flag Stops Clock'),
          value: _redFlagStopsClock,
          onChanged: (value) => setState(() => _redFlagStopsClock = value),
        ),
        SwitchListTile(
          title: const Text('Red Flag Deletes Passings'),
          value: _redFlagDeletesPassings,
          onChanged: (value) => setState(() => _redFlagDeletesPassings = value),
        ),
      ],
    );
  }

  Widget _buildAutoFinishTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        DropdownButtonFormField<String>(
          initialValue: _finishMode,
          decoration: const InputDecoration(labelText: 'Finish Mode'),
          items: ['Time', 'Laps', 'TimeAndLaps', 'TimeOrLaps', 'Individual']
              .map(
                  (value) => DropdownMenuItem(value: value, child: Text(value)))
              .toList(),
          onChanged: (value) {
            if (value != null) {
              setState(() => _finishMode = value);
            }
          },
        ),
        TextFormField(
          initialValue: _durationMinutes.toString(),
          decoration: const InputDecoration(labelText: 'Duration (minutes)'),
          keyboardType: TextInputType.number,
          onChanged: (value) => _durationMinutes = int.tryParse(value) ?? 0,
        ),
        TextFormField(
          initialValue: _laps.toString(),
          decoration: const InputDecoration(labelText: 'Laps'),
          keyboardType: TextInputType.number,
          onChanged: (value) => _laps = int.tryParse(value) ?? 0,
        ),
      ],
    );
  }

  Widget _buildQualificationTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        DropdownButtonFormField<String>(
          initialValue: _qualCriteria,
          decoration:
              const InputDecoration(labelText: 'Qualification Criteria'),
          items: ['None', 'Max % Best Lap', 'Max % Top X Avg']
              .map(
                  (value) => DropdownMenuItem(value: value, child: Text(value)))
              .toList(),
          onChanged: (value) {
            if (value != null) {
              setState(() => _qualCriteria = value);
            }
          },
        ),
        TextFormField(
          initialValue: _qualValue.toString(),
          decoration: const InputDecoration(labelText: 'Value (e.g. 107)'),
          keyboardType: TextInputType.number,
          onChanged: (value) => _qualValue = double.tryParse(value) ?? 0,
        ),
      ],
    );
  }

  Widget _buildTimelinesTab() {
    final hasEnabledStartFinish = _timelines.any(
      (timeline) =>
          timeline.type == SessionTimelineType.startFinish && timeline.enabled,
    );

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Configure control lines for this session and drag to reorder execution.',
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Add'),
                onPressed: () => _showTimelineEditor(),
              ),
            ],
          ),
        ),
        if (!hasEnabledStartFinish)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange),
            ),
            child: const Text(
              'Add at least one enabled Start/Finish line to save this session.',
            ),
          ),
        Expanded(
          child: _timelines.isEmpty
              ? const Center(
                  child: Text('No timelines configured.'),
                )
              : ReorderableListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                  itemCount: _timelines.length,
                  onReorder: _reorderTimelines,
                  buildDefaultDragHandles: false,
                  itemBuilder: (context, index) {
                    final timeline = _timelines[index];
                    final typeLabel = _timelineTypeLabel(timeline.type);
                    return Card(
                      key: ValueKey(timeline.id),
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: ListTile(
                        leading: CircleAvatar(
                          radius: 14,
                          child: Text('${index + 1}'),
                        ),
                        title: Text(timeline.name.isNotEmpty
                            ? timeline.name
                            : typeLabel),
                        subtitle: Text(
                          '$typeLabel • CP ${timeline.checkpointIndex}'
                          '${timeline.enabled ? '' : ' • Disabled'}',
                        ),
                        onTap: () => _showTimelineEditor(index: index),
                        trailing: SizedBox(
                          width: 120,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              IconButton(
                                tooltip: 'Edit',
                                icon: const Icon(Icons.edit_outlined),
                                onPressed: () =>
                                    _showTimelineEditor(index: index),
                              ),
                              IconButton(
                                tooltip: 'Delete',
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () => _deleteTimeline(index),
                              ),
                              ReorderableDragStartListener(
                                index: index,
                                child: const Icon(Icons.drag_handle),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
