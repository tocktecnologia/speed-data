
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:speed_data/features/models/event_model.dart';
import 'package:speed_data/features/models/race_session_model.dart';
import 'package:speed_data/features/services/firestore_service.dart';
import 'package:intl/intl.dart';
import 'package:speed_data/features/screens/admin/widgets/driver_picker.dart';

class CreateEventScreen extends StatefulWidget {
  final RaceEvent? event;

  const CreateEventScreen({Key? key, this.event}) : super(key: key);

  @override
  State<CreateEventScreen> createState() => _CreateEventScreenState();
}

class _CreateEventScreenState extends State<CreateEventScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _firestoreService = FirestoreService();
  
  DateTime _selectedDate = DateTime.now();
  DateTime? _selectedEndDate;
  String? _selectedTrackId;
  List<RaceSession> _sessions = [];
  List<String> _selectedDriverIds = [];

  @override
  void initState() {
    super.initState();
    if (widget.event != null) {
      _nameController.text = widget.event!.name;
      _selectedDate = widget.event!.date;
      _selectedEndDate = widget.event!.endDate;
      _selectedTrackId = widget.event!.trackId;
      _sessions = List.from(widget.event!.sessions);
      _selectedDriverIds = List.from(widget.event!.driverIds);
    } else {
      // Default sessions
      _sessions = [];
    }

  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  void _addSession() {
    setState(() {
      _sessions.add(RaceSession(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        type: SessionType.practice,
        status: SessionStatus.scheduled,
        scheduledTime: _selectedDate,
        durationMinutes: 30,
      ));
    });
  }

  void _removeSession(int index) {
    setState(() {
      _sessions.removeAt(index);
    });
  }

  Future<void> _deleteEvent() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Event?'),
        content: const Text(
            'Are you sure you want to delete this event? This action cannot be undone and will delete all sessions, competitors, and results associated with it.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _firestoreService.deleteEvent(widget.event!.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Event deleted successfully')),
          );
          Navigator.pop(context); // Return to list
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting event: $e')),
          );
        }
      }
    }
  }

  Future<void> _saveEvent() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedTrackId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a track')),
      );
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final event = RaceEvent(
      id: widget.event?.id ?? '',
      name: _nameController.text.trim(),
      trackId: _selectedTrackId!,
      organizerId: user.uid,
      date: _selectedDate,
      endDate: _selectedEndDate,
      driverIds: _selectedDriverIds,
      sessions: _sessions,
      groups: widget.event?.groups ?? [],
    );

    try {
      if (widget.event == null) {
        await _firestoreService.createEvent(event);
      } else {
        await _firestoreService.updateEvent(event);
      }
      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving event: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.event == null ? 'Create Event' : 'Edit Event'),
        backgroundColor: Colors.black,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Event Name'),
              validator: (value) =>
                  value == null || value.isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 16),
            ListTile(
              title: Text('Start Date: ${DateFormat('yyyy-MM-dd').format(_selectedDate)}'),
              trailing: const Icon(Icons.calendar_today),
              onTap: () => _selectDate(context),
            ),
            const SizedBox(height: 16),
            ListTile(
              title: Text(
                  _selectedEndDate == null 
                  ? 'End Date (Optional)' 
                  : 'End Date: ${DateFormat('yyyy-MM-dd').format(_selectedEndDate!)}'),
              trailing: const Icon(Icons.calendar_today_outlined),
              onTap: () async {
                 final picked = await showDatePicker(
                  context: context,
                  initialDate: _selectedEndDate ?? _selectedDate,
                  firstDate: _selectedDate,
                  lastDate: DateTime(2030),
                );
                if (picked != null) {
                  setState(() {
                    _selectedEndDate = picked;
                  });
                }
              },
            ),
            const SizedBox(height: 16),
            StreamBuilder<QuerySnapshot>(
              // Track picker must include current track when editing, even if
              // the track is not marked as "open".
              stream: FirebaseFirestore.instance.collection('races').snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const CircularProgressIndicator();
                final tracks = snapshot.data!.docs;
                final seenTrackIds = <String>{};
                final items = tracks
                    .where((doc) => seenTrackIds.add(doc.id))
                    .map((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final trackName = (data['name'] as String?)?.trim();
                  return DropdownMenuItem<String>(
                    value: doc.id,
                    child: Text(
                      (trackName == null || trackName.isEmpty)
                          ? doc.id
                          : trackName,
                    ),
                  );
                }).toList();

                final dropdownValue = (_selectedTrackId != null &&
                        seenTrackIds.contains(_selectedTrackId))
                    ? _selectedTrackId
                    : null;

                return DropdownButtonFormField<String>(
                  value: dropdownValue,
                  decoration: const InputDecoration(labelText: 'Track'),
                  items: items,
                  onChanged: (val) => setState(() => _selectedTrackId = val),
                  validator: (value) => value == null ? 'Please select a track' : null,
                );
              },
            ),
            const SizedBox(height: 32),
            SizedBox(
              height: 50,
              child: ElevatedButton(
                onPressed: _saveEvent,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.black),
                child: Text(widget.event == null ? 'CREATE EVENT' : 'SAVE CHANGES'),
              ),
            ),
             if (widget.event != null) ...[
              const SizedBox(height: 16),
              SizedBox(
                height: 50,
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _deleteEvent,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                  ),
                  child: const Text('DELETE EVENT'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
