
import 'package:flutter/material.dart';
import 'package:speed_data/features/models/race_session_model.dart';
import 'package:intl/intl.dart';

class SessionSettingsScreen extends StatefulWidget {
  final RaceSession? session;
  final Function(RaceSession) onSave;

  const SessionSettingsScreen({Key? key, this.session, required this.onSave}) : super(key: key);

  @override
  State<SessionSettingsScreen> createState() => _SessionSettingsScreenState();
}

class _SessionSettingsScreenState extends State<SessionSettingsScreen> with SingleTickerProviderStateMixin {
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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    
    if (widget.session != null) {
      final s = widget.session!;
      _nameController.text = s.name;
      _shortNameController.text = s.shortName;
      _date = s.scheduledTime;
      _time = TimeOfDay.fromDateTime(s.scheduledTime);
      _type = s.type;
      
      _startMethod = s.startMethod;
      _startOnFirstPassing = s.startOnFirstPassing;
      _minLapTime = s.minLapTimeSeconds;
      _redFlagStopsClock = s.redFlagStopsClock;
      _redFlagDeletesPassings = s.redFlagDeletesPassings;

      _finishMode = s.finishMode;
      _durationMinutes = s.durationMinutes;
      _laps = s.totalLaps ?? 0;

      _qualCriteria = s.qualificationCriteria;
      _qualValue = s.qualificationValue ?? 0;
    }
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    
    final scheduledTime = DateTime(
      _date.year, _date.month, _date.day, _time.hour, _time.minute
    );

    final newSession = RaceSession(
      id: widget.session?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
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
          )
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
        TextFormField(controller: _nameController, decoration: const InputDecoration(labelText: 'Name (e.g. Practice 1)')),
        TextFormField(controller: _shortNameController, decoration: const InputDecoration(labelText: 'Short Name')),
        ListTile(
          title: Text('Date: ${DateFormat('yyyy-MM-dd').format(_date)}'),
          trailing: const Icon(Icons.calendar_today),
          onTap: () async {
            final picked = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime(2020), lastDate: DateTime(2030));
            if (picked != null) setState(() => _date = picked);
          },
        ),
        ListTile(
          title: Text('Time: ${_time.format(context)}'),
          trailing: const Icon(Icons.access_time),
          onTap: () async {
            final picked = await showTimePicker(context: context, initialTime: _time);
            if (picked != null) setState(() => _time = picked);
          },
        ),
        DropdownButtonFormField<SessionType>(
          value: _type,
          decoration: const InputDecoration(labelText: 'Type'),
          items: SessionType.values.map((t) => DropdownMenuItem(value: t, child: Text(t.name.toUpperCase()))).toList(),
          onChanged: (v) => setState(() => _type = v!),
        ),
      ],
    );
  }

  Widget _buildTimingTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        DropdownButtonFormField<String>(
          value: _startMethod,
          decoration: const InputDecoration(labelText: 'Start Method'),
          items: ['First Passing', 'Flag', 'Staggered'].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
          onChanged: (v) => setState(() => _startMethod = v!),
        ),
        SwitchListTile(
          title: const Text('Start on First Passing'),
          value: _startOnFirstPassing,
          onChanged: (v) => setState(() => _startOnFirstPassing = v),
        ),
        TextFormField(
          initialValue: _minLapTime.toString(),
          decoration: const InputDecoration(labelText: 'Minimum Lap Time (sec)'),
          keyboardType: TextInputType.number,
          onChanged: (v) => _minLapTime = int.tryParse(v) ?? 0,
        ),
        SwitchListTile(
          title: const Text('Red Flag Stops Clock'),
          value: _redFlagStopsClock,
          onChanged: (v) => setState(() => _redFlagStopsClock = v),
        ),
         SwitchListTile(
          title: const Text('Red Flag Deletes Passings'),
          value: _redFlagDeletesPassings,
          onChanged: (v) => setState(() => _redFlagDeletesPassings = v),
        ),
      ],
    );
  }

  Widget _buildAutoFinishTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        DropdownButtonFormField<String>(
          value: _finishMode,
          decoration: const InputDecoration(labelText: 'Finish Mode'),
          items: ['Time', 'Laps', 'TimeAndLaps', 'TimeOrLaps', 'Individual'].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
          onChanged: (v) => setState(() => _finishMode = v!),
        ),
        TextFormField(
          initialValue: _durationMinutes.toString(),
          decoration: const InputDecoration(labelText: 'Duration (minutes)'),
           keyboardType: TextInputType.number,
          onChanged: (v) => _durationMinutes = int.tryParse(v) ?? 0,
        ),
        TextFormField(
          initialValue: _laps.toString(),
          decoration: const InputDecoration(labelText: 'Laps'),
           keyboardType: TextInputType.number,
          onChanged: (v) => _laps = int.tryParse(v) ?? 0,
        ),
      ],
    );
  }

  Widget _buildQualificationTab() {
    return ListView(
       padding: const EdgeInsets.all(16),
      children: [
         DropdownButtonFormField<String>(
          value: _qualCriteria,
          decoration: const InputDecoration(labelText: 'Qualification Criteria'),
          items: ['None', 'Max % Best Lap', 'Max % Top X Avg'].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
          onChanged: (v) => setState(() => _qualCriteria = v!),
        ),
        TextFormField(
          initialValue: _qualValue.toString(),
          decoration: const InputDecoration(labelText: 'Value (e.g. 107)'),
           keyboardType: TextInputType.number,
          onChanged: (v) => _qualValue = double.tryParse(v) ?? 0,
        ),
      ],
    );
  }

  Widget _buildTimelinesTab() {
     return const Center(child: Text('Timelines (Loops) Selection - Implementation Pending Track Data'));
  }
}
