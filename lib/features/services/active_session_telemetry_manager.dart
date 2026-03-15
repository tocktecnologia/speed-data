import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:speed_data/features/models/event_model.dart';
import 'package:speed_data/features/models/race_session_model.dart';
import 'package:speed_data/features/models/user_role.dart';
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
  int _authRevision = 0;
  bool _started = false;

  void _debugLog(String message) {
    if (!kDebugMode) return;
    final ts = DateTime.now().toIso8601String();
    debugPrint(
      '[ActiveSessionTelemetryManager][$ts]'
      '[uid:${_currentUid ?? '-'}]'
      '[event:${_currentEventId ?? '-'}]'
      '[session:${_currentSessionId ?? '-'}] $message',
    );
  }

  void start() {
    if (_started) return;
    _started = true;
    _debugLog('start');
    _authSubscription =
        FirebaseAuth.instance.authStateChanges().listen(_handleAuthChange);
  }

  void dispose() {
    _debugLog('dispose');
    _eventsSubscription?.cancel();
    _eventsSubscription = null;
    _authSubscription?.cancel();
    _authSubscription = null;
    _started = false;
  }

  void _handleAuthChange(User? user) {
    final authRevision = ++_authRevision;
    _debugLog('auth change -> uid=${user?.uid}, email=${user?.email}');
    _currentUid = user?.uid;
    _eventsSubscription?.cancel();
    _eventsSubscription = null;

    if (user == null) {
      _debugLog('auth change: no user, stopping telemetry');
      _stopTelemetry();
      return;
    }

    _resolveRoleAndSubscribe(user, authRevision);
  }

  Future<void> _resolveRoleAndSubscribe(User user, int authRevision) async {
    final role = await _firestoreService.getUserRole(user.uid);
    if (authRevision != _authRevision) return;

    if (role != UserRole.pilot) {
      _debugLog(
        'auth change: role=${role.toStringValue()}, telemetry disabled for this role',
      );
      _stopTelemetry();
      return;
    }

    _eventsSubscription = _firestoreService.getEventsStream().listen((events) {
      _debugLog('events stream update: events=${events.length}');
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

  int _compareEventPriority(RaceEvent a, RaceEvent b, DateTime now) {
    final aSession = _findActiveSession(a);
    final bSession = _findActiveSession(b);
    final aHasActive = aSession != null;
    final bHasActive = bSession != null;
    if (aHasActive != bHasActive) {
      return aHasActive ? -1 : 1;
    }

    final aInWindow = _isEventActiveNow(a, now);
    final bInWindow = _isEventActiveNow(b, now);
    if (aInWindow != bInWindow) {
      return aInWindow ? -1 : 1;
    }

    return b.date.compareTo(a.date);
  }

  Future<void> _handleEvents(List<RaceEvent> events) async {
    final uid = _currentUid;
    if (uid == null) return;

    final now = DateTime.now();
    final activeSessionCandidates = events
        .where((e) => _findActiveSession(e) != null)
        .toList()
      ..sort((a, b) => _compareEventPriority(a, b, now));

    if (activeSessionCandidates.isEmpty) {
      _debugLog('_handleEvents: no events with active session');
      _stopTelemetry();
      return;
    }
    _debugLog(
      '_handleEvents: candidates with active session=${activeSessionCandidates.length}',
    );

    final checks = await Future.wait(activeSessionCandidates.map((event) async {
      final isRegistered =
          await _firestoreService.isUserRegisteredInEvent(event.id, uid);
      _debugLog(
        '_handleEvents: event=${event.id}, inWindow=${_isEventActiveNow(event, now)}, '
        'registered=$isRegistered, sessions=${event.sessions.length}',
      );
      if (!isRegistered) return null;
      final session = _findActiveSession(event);
      if (session == null) return null;
      return {
        'event': event,
        'session': session,
        'inWindow': _isEventActiveNow(event, now)
      };
    }));

    final registeredWithActive =
        checks.whereType<Map<String, dynamic>>().toList()
          ..sort((a, b) {
            final aEvent = a['event'] as RaceEvent;
            final bEvent = b['event'] as RaceEvent;
            final aInWindow = a['inWindow'] == true;
            final bInWindow = b['inWindow'] == true;
            if (aInWindow != bInWindow) {
              return aInWindow ? -1 : 1;
            }
            return bEvent.date.compareTo(aEvent.date);
          });

    if (registeredWithActive.isEmpty) {
      _debugLog(
        '_handleEvents: no registered events with active session for uid=$uid',
      );
      _stopTelemetry();
      return;
    }

    final entry = registeredWithActive.first;
    final event = entry['event'] as RaceEvent;
    final session = entry['session'] as RaceSession;
    _debugLog(
        '_handleEvents: selected event=${event.id}, session=${session.id}');
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
    _debugLog(
      '_startTelemetryForSession: event=${event.id}, session=${session.id}, '
      'race=${event.trackId}, simulationOverride=${_telemetryService.simulationOverride}, '
      'sendToCloud=${_telemetryService.enableSendDataToCloud}',
    );

    if (_telemetryService.simulationOverride) {
      _debugLog(
          '_startTelemetryForSession: simulation override active, skipping recording start');
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
        _debugLog(
            '_startTelemetryForSession: startRecording race=${event.trackId}');
        await _telemetryService.startRecording(event.trackId, uid);
      } catch (e) {
        _debugLog('_startTelemetryForSession: startRecording failed: $e');
      }
    }
  }

  void _stopTelemetry() {
    _debugLog(
      '_stopTelemetry: isSimulating=${_telemetryService.isSimulating}, '
      'simulationOverride=${_telemetryService.simulationOverride}, '
      'isRecording=${_telemetryService.isRecording}',
    );
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
