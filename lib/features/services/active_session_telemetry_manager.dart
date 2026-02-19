import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:speed_data/features/models/event_model.dart';
import 'package:speed_data/features/models/race_session_model.dart';
import 'package:speed_data/features/services/firestore_service.dart';
import 'package:speed_data/features/services/telemetry_service.dart';

class ActiveSessionTelemetryManager {
  ActiveSessionTelemetryManager._internal();

  static final ActiveSessionTelemetryManager instance =
      ActiveSessionTelemetryManager._internal();

  final FirestoreService _firestoreService = FirestoreService();
  final TelemetryService _telemetryService = TelemetryService.instance;

  StreamSubscription<User?>? _authSubscription;
  StreamSubscription<List<RaceEvent>>? _eventsSubscription;

  String? _currentUid;
  String? _currentEventId;
  String? _currentSessionId;
  String? _currentRaceId;
  bool _started = false;

  void start() {
    if (_started) return;
    _started = true;
    _authSubscription =
        FirebaseAuth.instance.authStateChanges().listen(_handleAuthChange);
  }

  void dispose() {
    _eventsSubscription?.cancel();
    _eventsSubscription = null;
    _authSubscription?.cancel();
    _authSubscription = null;
    _started = false;
  }

  void _handleAuthChange(User? user) {
    _currentUid = user?.uid;
    _eventsSubscription?.cancel();
    _eventsSubscription = null;

    if (user == null) {
      _stopTelemetry();
      return;
    }

    _eventsSubscription = _firestoreService.getEventsStream().listen((events) {
      _handleEvents(events);
    });
  }

  DateTime _eventEndDate(RaceEvent event) {
    if (event.endDate != null) {
      final localEnd = event.endDate!.toLocal();
      final isMidnight = localEnd.hour == 0 &&
          localEnd.minute == 0 &&
          localEnd.second == 0 &&
          localEnd.millisecond == 0;
      if (isMidnight) {
        return DateTime(
            localEnd.year, localEnd.month, localEnd.day, 23, 59, 59, 999);
      }
      return localEnd;
    }
    final local = event.date.toLocal();
    return DateTime(local.year, local.month, local.day, 23, 59, 59, 999);
  }

  bool _isEventActiveNow(RaceEvent event, DateTime now) {
    final nowLocal = now.toLocal();
    final eventStartLocal = event.date.toLocal();
    final eventStart = DateTime(
        eventStartLocal.year, eventStartLocal.month, eventStartLocal.day);
    final eventEnd = _eventEndDate(event).toLocal();
    if (nowLocal.isBefore(eventStart)) return false;
    return nowLocal.isBefore(eventEnd) || nowLocal.isAtSameMomentAs(eventEnd);
  }

  RaceSession? _findActiveSession(RaceEvent event) {
    try {
      return event.sessions.firstWhere((s) => s.status == SessionStatus.active);
    } catch (_) {
      return null;
    }
  }

  Future<void> _handleEvents(List<RaceEvent> events) async {
    final uid = _currentUid;
    if (uid == null) return;

    final now = DateTime.now();
    final activeEvents =
        events.where((e) => _isEventActiveNow(e, now)).toList();

    if (activeEvents.isEmpty) {
      _stopTelemetry();
      return;
    }

    final checks = await Future.wait(activeEvents.map((event) async {
      final isRegistered =
          await _firestoreService.isUserRegisteredInEvent(event.id, uid);
      if (!isRegistered) return null;
      final session = _findActiveSession(event);
      if (session == null) return null;
      return {'event': event, 'session': session};
    }));

    final registeredWithActive =
        checks.whereType<Map<String, dynamic>>().toList()
          ..sort((a, b) {
            final aEvent = a['event'] as RaceEvent;
            final bEvent = b['event'] as RaceEvent;
            return aEvent.date.compareTo(bEvent.date);
          });

    if (registeredWithActive.isEmpty) {
      _stopTelemetry();
      return;
    }

    final entry = registeredWithActive.first;
    final event = entry['event'] as RaceEvent;
    final session = entry['session'] as RaceSession;
    await _startTelemetryForSession(event, session);
  }

  Future<void> _startTelemetryForSession(
      RaceEvent event, RaceSession session) async {
    final uid = _currentUid;
    if (uid == null) return;

    _currentEventId = event.id;
    _currentSessionId = session.id;
    _currentRaceId = event.trackId;

    _telemetryService.setSessionId(session.id);
    _telemetryService.enableSendDataToCloud =
        !_telemetryService.simulationOverride;

    if (_telemetryService.simulationOverride) {
      return;
    }

    final race = await _firestoreService.getRace(event.trackId);
    final checkpointsRaw = race?['checkpoints'];
    if (checkpointsRaw is List) {
      _telemetryService.setCheckpoints(
          checkpointsRaw.map((e) => Map<String, dynamic>.from(e)).toList());
    }
    _telemetryService.setTimelines(
      session.timelines
          .map((timeline) => timeline.toMap())
          .toList(growable: false),
    );

    if (!_telemetryService.isRecording ||
        _telemetryService.currentRaceId != event.trackId ||
        _telemetryService.currentUserId != uid) {
      try {
        await _telemetryService.startRecording(event.trackId, uid);
      } catch (_) {}
    }
  }

  void _stopTelemetry() {
    _currentEventId = null;
    _currentSessionId = null;
    _currentRaceId = null;
    _telemetryService.setSessionId(null);
    _telemetryService.setTimelines(const []);
    _telemetryService.enableSendDataToCloud = false;

    if (_telemetryService.isSimulating) {
      _telemetryService.stopSimulation();
      return;
    }

    if (_telemetryService.simulationOverride) {
      return;
    }

    if (_telemetryService.isRecording) {
      _telemetryService.stopRecording();
    }
  }
}
