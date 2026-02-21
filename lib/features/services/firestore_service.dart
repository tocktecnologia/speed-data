import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:speed_data/features/models/user_role.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:speed_data/features/models/event_model.dart';
import 'package:speed_data/features/models/race_session_model.dart';
import 'package:speed_data/features/models/competitor_model.dart';
import 'package:speed_data/features/models/passing_model.dart';
import 'package:speed_data/features/models/lap_analysis_model.dart';
import 'package:speed_data/features/models/crossing_model.dart';
import 'package:speed_data/features/models/session_analysis_summary_model.dart';
import 'package:speed_data/features/screens/admin/widgets/control_flags.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  void _debugLog(String message) {
    if (!kDebugMode) return;
    final ts = DateTime.now().toIso8601String();
    debugPrint('[FirestoreService][$ts] $message');
  }

  String _normalizeEmail(String email) => email.trim().toLowerCase();

  DateTime? _asDateTime(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is num) return DateTime.fromMillisecondsSinceEpoch(value.toInt());
    return null;
  }

  double _asDouble(dynamic value, double fallback) {
    if (value is num) return value.toDouble();
    return fallback;
  }

  DocumentReference<Map<String, dynamic>> _raceParticipantRef(
      String raceId, String uid) {
    return _db
        .collection('races')
        .doc(raceId)
        .collection('participants')
        .doc(uid);
  }

  DocumentReference<Map<String, dynamic>>? _eventSessionParticipantRef(
    String? eventId,
    String? sessionId,
    String uid,
  ) {
    if (eventId == null ||
        eventId.isEmpty ||
        sessionId == null ||
        sessionId.isEmpty) {
      return null;
    }
    return _db
        .collection('events')
        .doc(eventId)
        .collection('sessions')
        .doc(sessionId)
        .collection('participants')
        .doc(uid);
  }

  // --- Users ---

  Future<UserRole> getUserRole(String uid) async {
    try {
      DocumentSnapshot doc = await _db.collection('users').doc(uid).get();
      if (doc.exists && doc.data() != null) {
        final data = doc.data() as Map<String, dynamic>;
        return UserRole.fromString(data['role']);
      }
      return UserRole.unknown;
    } catch (e) {
      print('Error getting user role: $e');
      return UserRole.unknown;
    }
  }

  Future<void> setUserRole(String uid, UserRole role, {String? email}) async {
    final data = {
      'role': role.toStringValue(),
    };
    if (email != null) data['email'] = email;

    await _db.collection('users').doc(uid).set(data, SetOptions(merge: true));
  }

  Future<void> updatePilotProfile(String uid, String name, int color,
      {String? email}) async {
    final data = {
      'name': name,
      'color': color,
    };
    if (email != null) data['email'] = email;

    await _db.collection('users').doc(uid).set(data, SetOptions(merge: true));
  }

  Future<Map<String, dynamic>?> getUserByEmail(String email) async {
    try {
      final trimmedEmail = email.trim();
      final variants = [trimmedEmail, trimmedEmail.toLowerCase()];

      for (var variant in variants.toSet()) {
        final snapshot = await _db
            .collection('users')
            .where('email', isEqualTo: variant)
            .limit(1)
            .get();

        if (snapshot.docs.isNotEmpty) {
          final doc = snapshot.docs.first;
          final data = doc.data();
          data['uid'] = doc.id;

          // Normalize name/display_name
          if (data.containsKey('display_name') && !data.containsKey('name')) {
            data['name'] = data['display_name'];
          } else if (data.containsKey('name') &&
              !data.containsKey('display_name')) {
            data['display_name'] = data['name'];
          }

          return data;
        }
      }
    } catch (e) {
      print('Error getting user by email: $e');
    }
    return null;
  }

  /// Simulation config resolution:
  /// 1) Global defaults in `app_config/simulation`
  /// 2) User override in `simulation_testers/{normalized_email}`
  ///
  /// Expected fields:
  /// - enabled_default (bool)
  /// - default_speed_mps (num)
  /// - auto_start_default (bool)
  ///
  /// User override fields:
  /// - enabled (bool)
  /// - speed_mps (num)
  /// - auto_start (bool)
  /// - valid_from (Timestamp/int, optional)
  /// - valid_until (Timestamp/int, optional)
  Future<Map<String, dynamic>> getSimulationRuntimeConfig(
      {String? email}) async {
    bool enabled = false;
    bool autoStart = true;
    double speedMps = 40.0;
    String source = 'defaults';

    try {
      final globalDoc =
          await _db.collection('app_config').doc('simulation').get();
      final globalData = globalDoc.data();
      if (globalData != null) {
        enabled = globalData['enabled_default'] is bool
            ? globalData['enabled_default']
            : enabled;
        autoStart = globalData['auto_start_default'] is bool
            ? globalData['auto_start_default']
            : autoStart;
        speedMps = _asDouble(globalData['default_speed_mps'], speedMps);
        source = 'global';
      }
    } catch (e) {
      print('Error loading global simulation config: $e');
    }

    final normalizedEmail =
        (email == null || email.trim().isEmpty) ? null : _normalizeEmail(email);
    if (normalizedEmail != null) {
      try {
        final userDoc = await _db
            .collection('simulation_testers')
            .doc(normalizedEmail)
            .get();
        final userData = userDoc.data();
        if (userData != null) {
          final now = DateTime.now();
          final validFrom = _asDateTime(userData['valid_from']);
          final validUntil = _asDateTime(userData['valid_until']);
          final inWindow = (validFrom == null || !now.isBefore(validFrom)) &&
              (validUntil == null || !now.isAfter(validUntil));

          if (inWindow) {
            enabled =
                userData['enabled'] is bool ? userData['enabled'] : enabled;
            autoStart = userData['auto_start'] is bool
                ? userData['auto_start']
                : autoStart;
            speedMps = _asDouble(userData['speed_mps'], speedMps);
            source = 'user';
          } else {
            // Keep global/default values when user override is out of validity window.
            source = 'global_out_of_window';
          }
        }
      } catch (e) {
        print('Error loading user simulation config: $e');
      }
    }

    return {
      'enabled': enabled,
      'auto_start': autoStart,
      'speed_mps': speedMps,
      'email': normalizedEmail,
      'source': source,
    };
  }

  /// Local timing config resolution:
  /// 1) Global defaults in `app_config/local_timing`
  /// 2) User override in `local_timing_testers/{normalized_email}`
  ///
  /// Expected fields:
  /// - enabled_default (bool)
  ///
  /// User override fields:
  /// - enabled (bool)
  /// - valid_from (Timestamp/int, optional)
  /// - valid_until (Timestamp/int, optional)
  Future<Map<String, dynamic>> getLocalTimingRuntimeConfig(
      {String? email}) async {
    bool enabled = false;
    String source = 'defaults';

    try {
      final globalDoc =
          await _db.collection('app_config').doc('local_timing').get();
      final globalData = globalDoc.data();
      if (globalData != null) {
        enabled = globalData['enabled_default'] is bool
            ? globalData['enabled_default']
            : enabled;
        source = 'global';
      }
    } catch (e) {
      print('Error loading global local timing config: $e');
    }

    final normalizedEmail =
        (email == null || email.trim().isEmpty) ? null : _normalizeEmail(email);
    if (normalizedEmail != null) {
      try {
        final userDoc = await _db
            .collection('local_timing_testers')
            .doc(normalizedEmail)
            .get();
        final userData = userDoc.data();
        if (userData != null) {
          final now = DateTime.now();
          final validFrom = _asDateTime(userData['valid_from']);
          final validUntil = _asDateTime(userData['valid_until']);
          final inWindow = (validFrom == null || !now.isBefore(validFrom)) &&
              (validUntil == null || !now.isAfter(validUntil));

          if (inWindow) {
            enabled =
                userData['enabled'] is bool ? userData['enabled'] : enabled;
            source = 'user';
          } else {
            source = 'global_out_of_window';
          }
        }
      } catch (e) {
        print('Error loading user local timing config: $e');
      }
    }

    return {
      'enabled': enabled,
      'email': normalizedEmail,
      'source': source,
    };
  }

  Future<void> setSimulationDefaults({
    required bool enabledDefault,
    required bool autoStartDefault,
    required double defaultSpeedMps,
    String? updatedBy,
  }) async {
    await _db.collection('app_config').doc('simulation').set({
      'enabled_default': enabledDefault,
      'auto_start_default': autoStartDefault,
      'default_speed_mps': defaultSpeedMps,
      'updated_by': updatedBy,
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> setSimulationTesterByEmail({
    required String email,
    required bool enabled,
    bool autoStart = true,
    double? speedMps,
    DateTime? validFrom,
    DateTime? validUntil,
    String? notes,
    String? updatedBy,
  }) async {
    final normalizedEmail = _normalizeEmail(email);
    await _db.collection('simulation_testers').doc(normalizedEmail).set({
      'email': normalizedEmail,
      'enabled': enabled,
      'auto_start': autoStart,
      'speed_mps': speedMps,
      'valid_from': validFrom != null ? Timestamp.fromDate(validFrom) : null,
      'valid_until': validUntil != null ? Timestamp.fromDate(validUntil) : null,
      'notes': notes,
      'updated_by': updatedBy,
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // --- Races ---

  // --- Events ---

  Future<String> createEvent(RaceEvent event) async {
    final docRef = await _db.collection('events').add(event.toMap());
    return docRef.id;
  }

  Future<void> updateEvent(RaceEvent event) async {
    await _db.collection('events').doc(event.id).update(event.toMap());
  }

  Stream<List<RaceEvent>> getEventsStream({String? organizerId}) {
    Query query = _db.collection('events');

    if (organizerId != null) {
      query = query.where('organizer_id', isEqualTo: organizerId);
    }

    return query.orderBy('date', descending: false).snapshots().map(
        (snapshot) => snapshot.docs
            .map((doc) =>
                RaceEvent.fromMap(doc.id, doc.data() as Map<String, dynamic>))
            .toList());
  }

  Stream<RaceEvent> getEventStream(String eventId) {
    return _db.collection('events').doc(eventId).snapshots().map((doc) {
      if (doc.exists && doc.data() != null) {
        return RaceEvent.fromMap(doc.id, doc.data() as Map<String, dynamic>);
      } else {
        throw Exception('Event not found');
      }
    });
  }

  Future<RaceEvent?> getEvent(String eventId,
      {bool forceServer = false}) async {
    try {
      final doc = forceServer
          ? await _db
              .collection('events')
              .doc(eventId)
              .get(const GetOptions(source: Source.server))
          : await _db.collection('events').doc(eventId).get();
      if (doc.exists && doc.data() != null) {
        return RaceEvent.fromMap(doc.id, doc.data() as Map<String, dynamic>);
      }
      return null;
    } catch (e) {
      print('Error getting event: $e');
      return null;
    }
  }

  Future<void> deleteEvent(String eventId) async {
    await _db.collection('events').doc(eventId).delete();
  }

  // Find the current event for a track. By default, returns a fallback event
  // when there is no event in the current date window.
  Future<RaceEvent?> getActiveEventForTrack(
    String trackId, {
    bool allowFallback = true,
    bool requireActiveSession = false,
    bool forceServer = false,
  }) async {
    try {
      _debugLog(
        'getActiveEventForTrack(trackId=$trackId, allowFallback=$allowFallback, '
        'requireActiveSession=$requireActiveSession, forceServer=$forceServer)',
      );
      final query = _db
          .collection('events')
          .where('track_id', isEqualTo: trackId)
          .limit(50);
      final snapshot = forceServer
          ? await query.get(const GetOptions(source: Source.server))
          : await query.get();
      _debugLog(
        'getActiveEventForTrack: fetched docs=${snapshot.docs.length}',
      );

      if (snapshot.docs.isNotEmpty) {
        final events = snapshot.docs
            .map((doc) => RaceEvent.fromMap(doc.id, doc.data()))
            .toList()
          ..sort((a, b) => b.date.compareTo(a.date));
        final now = DateTime.now();
        RaceEvent? fallbackAny;
        RaceEvent? fallbackWithActiveSession;
        for (final event in events) {
          fallbackAny ??= event;
          final eventStart = DateTime(event.date.toLocal().year,
              event.date.toLocal().month, event.date.toLocal().day);
          final end = event.endDate?.toLocal() ??
              DateTime(event.date.toLocal().year, event.date.toLocal().month,
                  event.date.toLocal().day, 23, 59, 59, 999);
          final hasActiveSession =
              event.sessions.any((s) => s.status == SessionStatus.active);
          if (hasActiveSession) {
            fallbackWithActiveSession ??= event;
          }
          _debugLog(
            'getActiveEventForTrack: candidate event=${event.id}, '
            'date=${event.date.toIso8601String()}, '
            'end=${end.toIso8601String()}, '
            'sessions=${event.sessions.length}, hasActiveSession=$hasActiveSession',
          );
          if ((now.isAfter(eventStart) || now.isAtSameMomentAs(eventStart)) &&
              (now.isBefore(end) || now.isAtSameMomentAs(end)) &&
              (!requireActiveSession || hasActiveSession)) {
            _debugLog(
              'getActiveEventForTrack: selected by date window -> ${event.id}',
            );
            return event;
          }
        }
        if (allowFallback) {
          if (requireActiveSession) {
            _debugLog(
              'getActiveEventForTrack: returning fallbackWithActiveSession='
              '${fallbackWithActiveSession?.id ?? 'null'}',
            );
            return fallbackWithActiveSession;
          }
          _debugLog(
            'getActiveEventForTrack: returning fallbackAny=${fallbackAny?.id ?? 'null'}',
          );
          return fallbackAny;
        }
        _debugLog('getActiveEventForTrack: no match and no fallback');
        return null;
      }
    } catch (e) {
      print('Error getting active event for track: $e');
    }
    return null;
  }

  // --- Competitors (Sub-collection of Events) ---

  Future<void> addCompetitor(String eventId, Competitor competitor) async {
    await _db
        .collection('events')
        .doc(eventId)
        .collection('competitors')
        .doc(competitor.id)
        .set(competitor.toMap());
  }

  Future<void> removeCompetitor(String eventId, String competitorId) async {
    await _db
        .collection('events')
        .doc(eventId)
        .collection('competitors')
        .doc(competitorId)
        .delete();
  }

  Stream<RaceSession?> getEventActiveSessionStream(String eventId) {
    return _db.collection('events').doc(eventId).snapshots().map((doc) {
      if (doc.exists && doc.data() != null) {
        final event =
            RaceEvent.fromMap(doc.id, doc.data() as Map<String, dynamic>);
        try {
          return event.sessions
              .firstWhere((s) => s.status == SessionStatus.active);
        } catch (_) {
          return null;
        }
      }
      return null;
    });
  }

  Stream<List<Competitor>> getCompetitorsStream(String eventId) {
    return _db
        .collection('events')
        .doc(eventId)
        .collection('competitors')
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => Competitor.fromMap(doc.data()))
            .toList());
  }

  /// Get competitor by user UID from event
  Future<Competitor?> getCompetitorByUid(String eventId, String uid) async {
    try {
      final snapshot = await _db
          .collection('events')
          .doc(eventId)
          .collection('competitors')
          .where('user_id', isEqualTo: uid)
          .limit(1)
          .get();

      if (snapshot.docs.isNotEmpty) {
        return Competitor.fromMap(snapshot.docs.first.data());
      }
      return null;
    } catch (e) {
      print('Error getting competitor by UID: $e');
      return null;
    }
  }

  Future<List<Competitor>> getCompetitors(String eventId) async {
    final snapshot = await _db
        .collection('events')
        .doc(eventId)
        .collection('competitors')
        .get();
    return snapshot.docs.map((doc) => Competitor.fromMap(doc.data())).toList();
  }

  // --- Races ---

  Future<String> createRace(String name, String creatorId,
      {List<Map<String, double>>? checkpoints,
      List<Map<String, double>>? routePath}) async {
    DocumentReference ref = await _db.collection('races').add({
      'name': name,
      'creator_id': creatorId,
      'created_at': FieldValue.serverTimestamp(),
      'status': 'open',
      'checkpoints': checkpoints ?? [],
      'route_path': routePath ?? [],
    });
    return ref.id;
  }

  Future<void> updateRaceFlag(String raceId, RaceFlag flag) async {
    await _db.collection('races').doc(raceId).update({
      'flag': flag.name, // Storing strict enum name
      'flag_updated_at': FieldValue.serverTimestamp(),
    });
  }

  Future<Map<String, dynamic>?> getRace(String raceId,
      {bool forceServer = false}) async {
    final doc = forceServer
        ? await _db
            .collection('races')
            .doc(raceId)
            .get(const GetOptions(source: Source.server))
        : await _db.collection('races').doc(raceId).get();
    return doc.data() as Map<String, dynamic>?;
  }

  Future<void> updateRace(String raceId,
      {String? name,
      List<Map<String, double>>? checkpoints,
      List<Map<String, double>>? routePath}) async {
    final Map<String, dynamic> data = {};
    if (name != null) data['name'] = name;
    if (checkpoints != null) data['checkpoints'] = checkpoints;
    if (routePath != null) data['route_path'] = routePath;

    await _db.collection('races').doc(raceId).update(data);
  }

  Future<void> deleteRace(String raceId) async {
    // Note: This only deletes the race document. Subcollections (participants) are not automatically deleted in Firestore.
    // Ideally, a Cloud Function should handle recursive deletion, or we delete subcollections manually here.
    // For now, we'll just delete the race document as per typical client-side implementation constraints.
    await _db.collection('races').doc(raceId).delete();
  }

  Stream<QuerySnapshot> getOpenRaces() {
    return _db
        .collection('races')
        .where('status', isEqualTo: 'open')
        // .orderBy('created_at', descending: true) // Commented out to fix potential index issue
        .snapshots();
  }

  Future<Map<String, dynamic>?> getUserProfile(String uid) async {
    try {
      DocumentSnapshot doc = await _db.collection('users').doc(uid).get();
      if (doc.exists) {
        return doc.data() as Map<String, dynamic>;
      }
    } catch (e) {
      print('Error getting user profile: $e');
    }
    return null;
  }

  Future<bool> isUserRegisteredInEvent(String eventId, String uid) async {
    try {
      _debugLog('isUserRegisteredInEvent(eventId=$eventId, uid=$uid)');
      final uidSnapshot = await _db
          .collection('events')
          .doc(eventId)
          .collection('competitors')
          .where('uid', isEqualTo: uid)
          .limit(1)
          .get();
      if (uidSnapshot.docs.isNotEmpty) {
        _debugLog(
          'isUserRegisteredInEvent: matched by competitors.uid (${uidSnapshot.docs.first.id})',
        );
        return true;
      }

      final userIdSnapshot = await _db
          .collection('events')
          .doc(eventId)
          .collection('competitors')
          .where('user_id', isEqualTo: uid)
          .limit(1)
          .get();
      if (userIdSnapshot.docs.isNotEmpty) {
        _debugLog(
          'isUserRegisteredInEvent: matched by competitors.user_id (${userIdSnapshot.docs.first.id})',
        );
      } else {
        _debugLog('isUserRegisteredInEvent: no match in competitors');
      }
      return userIdSnapshot.docs.isNotEmpty;
    } catch (e) {
      print('Error checking registration: $e');
      return false;
    }
  }

  Future<void> joinRace(
      String raceId, String uid, String displayName, int color) async {
    // Try to get the name from the user profile first
    String finalName = displayName;
    int finalColor = color;

    try {
      DocumentSnapshot userDoc = await _db.collection('users').doc(uid).get();
      if (userDoc.exists) {
        final data = userDoc.data() as Map<String, dynamic>;
        if (data.containsKey('name') &&
            data['name'] != null &&
            data['name'].toString().isNotEmpty) {
          finalName = data['name'];
        }
        if (data.containsKey('color') && data['color'] != null) {
          if (data['color'] is int) {
            finalColor = data['color'];
          } else if (data['color'] is String) {
            finalColor = int.tryParse(data['color']) ?? finalColor;
          }
        }
      }
    } catch (e) {
      print('Error fetching user profile for join: $e');
    }

    await _db
        .collection('races')
        .doc(raceId)
        .collection('participants')
        .doc(uid)
        .set({
      'uid': uid,
      'display_name': finalName,
      'color': finalColor.toString(),
      'joined_at': FieldValue.serverTimestamp(),
    });
  }

  Stream<DocumentSnapshot> getRaceStream(String raceId) {
    return _db.collection('races').doc(raceId).snapshots();
  }

  Stream<QuerySnapshot> getUsersStream() {
    return _db.collection('users').snapshots();
  }

  // --- Telemetry ---

  /// Updates the current live location of a pilot in a race
  Future<void> updatePilotLocation({
    required String raceId,
    required String uid,
    required double lat,
    required double lng,
    required double speed,
    required double heading,
    required DateTime timestamp,
  }) async {
    // Structure: races/{raceId}/participants/{uid}
    // We update the 'current' field (Map) on the participant document itself.
    // This avoids an extra subcollection and document layer.
    await _db
        .collection('races')
        .doc(raceId)
        .collection('participants')
        .doc(uid)
        .set({
      'current': {
        'lat': lat,
        'lng': lng,
        'speed': speed,
        'heading': heading,
        'timestamp': timestamp.millisecondsSinceEpoch,
        'last_updated': FieldValue.serverTimestamp(),
      }
    }, SetOptions(merge: true));
  }

  /// Sends a batch of telemetry data to the ingestion Cloud Function
  Future<void> sendTelemetryBatch(
      String raceId,
      String uid,
      List<Map<String, dynamic>> points,
      List<Map<String, dynamic>>? checkpoints,
      String? sessionId,
      {String? eventId,
      List<Map<String, dynamic>>? timelines,
      List<Map<String, dynamic>>? localLapClosures}) async {
    try {
      final callable =
          FirebaseFunctions.instance.httpsCallable('ingestTelemetry');
      await callable.call({
        'raceId': raceId,
        'eventId': eventId,
        'uid': uid,
        'points': points,
        'checkpoints': checkpoints,
        'timelines': timelines,
        'session': sessionId,
        'localLapClosures': localLapClosures,
      });
    } catch (e) {
      print('Error sending telemetry batch: $e');
      rethrow; // Re-throw to handle in service (e.g. keep in buffer)
    }
  }

  Stream<QuerySnapshot> getRaceLocations(
    String raceId, {
    String? eventId,
    String? sessionId,
  }) {
    if (eventId != null &&
        eventId.isNotEmpty &&
        sessionId != null &&
        sessionId.isNotEmpty) {
      return _db
          .collection('events')
          .doc(eventId)
          .collection('sessions')
          .doc(sessionId)
          .collection('participants')
          .snapshots();
    }

    // Legacy fallback
    return _db
        .collection('races')
        .doc(raceId)
        .collection('participants')
        .snapshots();
  }

  Stream<QuerySnapshot> getPilotSessions(String raceId, String uid,
      {String? eventId}) {
    if (eventId != null && eventId.isNotEmpty) {
      return _db
          .collection('events')
          .doc(eventId)
          .collection('sessions')
          .snapshots();
    }

    return _db
        .collection('races')
        .doc(raceId)
        .collection('participants')
        .doc(uid)
        .collection('sessions')
        .snapshots();
  }

  Stream<QuerySnapshot> getSessionLaps(
    String raceId,
    String uid,
    String sessionId, {
    String? eventId,
  }) {
    final eventParticipant =
        _eventSessionParticipantRef(eventId, sessionId, uid);
    if (eventParticipant != null) {
      return eventParticipant
          .collection('laps')
          .orderBy('number', descending: true)
          .snapshots();
    }

    return _raceParticipantRef(raceId, uid)
        .collection('sessions')
        .doc(sessionId)
        .collection('laps')
        .orderBy('number', descending: true)
        .snapshots();
  }

  Stream<List<LapAnalysisModel>> getSessionLapsModels(
    String raceId,
    String uid,
    String sessionId, {
    String? eventId,
  }) {
    final eventParticipant =
        _eventSessionParticipantRef(eventId, sessionId, uid);
    final stream = eventParticipant != null
        ? eventParticipant
            .collection('laps')
            .orderBy('number', descending: true)
            .snapshots()
        : _raceParticipantRef(raceId, uid)
            .collection('sessions')
            .doc(sessionId)
            .collection('laps')
            .orderBy('number', descending: true)
            .snapshots();

    return stream.map((snapshot) => snapshot.docs
        .map((doc) => LapAnalysisModel.fromMap(
            doc.id, doc.data() as Map<String, dynamic>))
        .toList());
  }

  Stream<Map<String, List<LapAnalysisModel>>> getSessionParticipantsLapsModels(
    String raceId, {
    String? sessionId,
    String? eventId,
  }) {
    if (sessionId == null || sessionId.isEmpty) {
      return Stream<Map<String, List<LapAnalysisModel>>>.value(const {});
    }

    final Stream<QuerySnapshot> participantsStream =
        (eventId != null && eventId.isNotEmpty)
            ? _db
                .collection('events')
                .doc(eventId)
                .collection('sessions')
                .doc(sessionId)
                .collection('participants')
                .snapshots()
            : _db
                .collection('races')
                .doc(raceId)
                .collection('participants')
                .snapshots();

    late StreamController<Map<String, List<LapAnalysisModel>>> controller;
    StreamSubscription<QuerySnapshot>? participantsSubscription;
    final Map<String, StreamSubscription<List<LapAnalysisModel>>>
        lapSubscriptions = {};
    final Map<String, List<LapAnalysisModel>> lapsByParticipant = {};

    void syncParticipantSubscriptions(Set<String> activeUids) {
      final staleUids = lapSubscriptions.keys
          .where((uid) => !activeUids.contains(uid))
          .toList(growable: false);
      for (final uid in staleUids) {
        lapSubscriptions.remove(uid)?.cancel();
        lapsByParticipant.remove(uid);
      }

      for (final uid in activeUids) {
        if (lapSubscriptions.containsKey(uid)) continue;
        lapSubscriptions[uid] = getSessionLapsModels(
          raceId,
          uid,
          sessionId,
          eventId: eventId,
        ).listen(
          (laps) {
            lapsByParticipant[uid] = laps;
            if (!controller.isClosed) {
              controller.add(
                  Map<String, List<LapAnalysisModel>>.from(lapsByParticipant));
            }
          },
          onError: (error, stackTrace) {
            if (!controller.isClosed) {
              controller.addError(error, stackTrace);
            }
          },
        );
      }

      if (!controller.isClosed) {
        controller
            .add(Map<String, List<LapAnalysisModel>>.from(lapsByParticipant));
      }
    }

    controller = StreamController<Map<String, List<LapAnalysisModel>>>(
      onListen: () {
        participantsSubscription = participantsStream.listen(
          (snapshot) {
            final activeUids = snapshot.docs
                .map((doc) => doc.id.trim())
                .where((uid) => uid.isNotEmpty)
                .toSet();
            syncParticipantSubscriptions(activeUids);
          },
          onError: (error, stackTrace) {
            if (!controller.isClosed) {
              controller.addError(error, stackTrace);
            }
          },
        );
      },
      onCancel: () async {
        await participantsSubscription?.cancel();
        for (final subscription in lapSubscriptions.values) {
          await subscription.cancel();
        }
        lapSubscriptions.clear();
      },
    );

    return controller.stream;
  }

  Stream<QuerySnapshot> getLaps(
    String raceId,
    String uid, {
    String? sessionId,
    String? eventId,
  }) {
    if (sessionId != null) {
      final eventParticipant =
          _eventSessionParticipantRef(eventId, sessionId, uid);
      if (eventParticipant != null) {
        return eventParticipant
            .collection('laps')
            .orderBy('number', descending: true)
            .snapshots();
      }
      return _raceParticipantRef(raceId, uid)
          .collection('sessions')
          .doc(sessionId)
          .collection('laps')
          .orderBy('number', descending: true)
          .snapshots();
    }
    return _raceParticipantRef(raceId, uid)
        .collection('laps')
        .orderBy('number', descending: true)
        .snapshots();
  }

  Stream<List<LapAnalysisModel>> getLapsModels(
    String raceId,
    String uid, {
    String? sessionId,
    String? eventId,
  }) {
    if (sessionId != null) {
      return getSessionLapsModels(raceId, uid, sessionId, eventId: eventId);
    }

    return _raceParticipantRef(raceId, uid)
        .collection('laps')
        .orderBy('number', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => LapAnalysisModel.fromMap(
                doc.id, doc.data() as Map<String, dynamic>))
            .toList());
  }

  Stream<List<CrossingModel>> getSessionCrossings(
    String raceId,
    String uid,
    String sessionId, {
    String? eventId,
  }) {
    final eventParticipant =
        _eventSessionParticipantRef(eventId, sessionId, uid);
    final stream = eventParticipant != null
        ? eventParticipant
            .collection('crossings')
            .orderBy('crossed_at_ms', descending: false)
            .snapshots()
        : _raceParticipantRef(raceId, uid)
            .collection('sessions')
            .doc(sessionId)
            .collection('crossings')
            .orderBy('crossed_at_ms', descending: false)
            .snapshots();

    return stream.map((snapshot) => snapshot.docs
        .map((doc) =>
            CrossingModel.fromMap(doc.id, doc.data() as Map<String, dynamic>))
        .toList());
  }

  Stream<SessionAnalysisSummaryModel?> getSessionAnalysisSummary(
    String raceId,
    String uid,
    String sessionId, {
    String? eventId,
  }) {
    final eventParticipant =
        _eventSessionParticipantRef(eventId, sessionId, uid);
    final stream = eventParticipant != null
        ? _db
            .collection('events')
            .doc(eventId)
            .collection('sessions')
            .doc(sessionId)
            .collection('analysis')
            .doc('summary')
            .snapshots()
        : _raceParticipantRef(raceId, uid)
            .collection('sessions')
            .doc(sessionId)
            .collection('analysis')
            .doc('summary')
            .snapshots();

    return stream.map((doc) {
      if (!doc.exists || doc.data() == null) return null;
      return SessionAnalysisSummaryModel.fromMap(
          doc.data() as Map<String, dynamic>);
    });
  }

  Stream<SessionAnalysisSummaryModel?> getSessionLeaderboardSummary(
    String raceId, {
    String? sessionId,
    String? eventId,
  }) {
    if (sessionId == null || sessionId.isEmpty) {
      return Stream<SessionAnalysisSummaryModel?>.value(null);
    }

    if (eventId != null && eventId.isNotEmpty) {
      return _db
          .collection('events')
          .doc(eventId)
          .collection('sessions')
          .doc(sessionId)
          .collection('analysis')
          .doc('summary')
          .snapshots()
          .map((doc) {
        if (!doc.exists || doc.data() == null) return null;
        return SessionAnalysisSummaryModel.fromMap(
            doc.data() as Map<String, dynamic>);
      });
    }

    return _db
        .collection('races')
        .doc(raceId)
        .collection('analysis')
        .doc('summary')
        .snapshots()
        .map((doc) {
      if (!doc.exists || doc.data() == null) return null;
      return SessionAnalysisSummaryModel.fromMap(
          doc.data() as Map<String, dynamic>);
    });
  }

  Future<void> setSessionLapValidity({
    required String raceId,
    required String uid,
    required String sessionId,
    required String lapId,
    required bool valid,
    String? eventId,
  }) async {
    final payload = <String, dynamic>{
      'valid': valid,
      'invalid_reasons': valid ? <String>[] : <String>['manual_invalid'],
      'manual_override': true,
      'manual_override_at': FieldValue.serverTimestamp(),
      'manual_override_source': 'pilot_lap_times',
    };

    final writes = <Future<void>>[];

    final eventParticipant =
        _eventSessionParticipantRef(eventId, sessionId, uid);
    if (eventParticipant != null) {
      writes.add(
        eventParticipant
            .collection('laps')
            .doc(lapId)
            .set(payload, SetOptions(merge: true)),
      );
    }

    writes.add(
      _raceParticipantRef(raceId, uid)
          .collection('sessions')
          .doc(sessionId)
          .collection('laps')
          .doc(lapId)
          .set(payload, SetOptions(merge: true)),
    );

    // Legacy compatibility path.
    writes.add(
      _raceParticipantRef(raceId, uid)
          .collection('laps')
          .doc(lapId)
          .set(payload, SetOptions(merge: true)),
    );

    await Future.wait(writes);
  }

  Stream<QuerySnapshot> getHistorySessions(String raceId, String uid) {
    return _db
        .collection('races')
        .doc(raceId)
        .collection('participants')
        .doc(uid)
        .collection('history_sessions')
        .orderBy('archived_at', descending: true)
        .snapshots();
  }

  Stream<QuerySnapshot> getHistorySessionLaps(
      String raceId, String uid, String historySessionId) {
    return _db
        .collection('races')
        .doc(raceId)
        .collection('participants')
        .doc(uid)
        .collection('history_sessions')
        .doc(historySessionId)
        .collection('laps')
        .orderBy('number', descending: true)
        .snapshots();
  }

  Future<void> clearRaceParticipantsLaps(String raceId) async {
    final participantsRef =
        _db.collection('races').doc(raceId).collection('participants');

    final snapshot = await participantsRef.get();

    for (var doc in snapshot.docs) {
      // 1. Delete direct 'laps' subcollection if it exists
      await _deleteCollection(doc.reference.collection('laps'));
    }
  }

  Future<void> clearRaceParticipants(String raceId) async {
    final participantsRef =
        _db.collection('races').doc(raceId).collection('participants');
    await _deleteCollection(participantsRef);
  }

  Future<void> _deleteCollection(CollectionReference collection) async {
    final snapshot = await collection.get();
    if (snapshot.docs.isEmpty) return;

    WriteBatch batch = _db.batch();
    int count = 0;
    for (var doc in snapshot.docs) {
      batch.delete(doc.reference);
      count++;
      if (count >= 450) {
        await batch.commit();
        batch = _db.batch();
        count = 0;
      }
    }
    if (count > 0) await batch.commit();
  }

  Future<void> _deleteQuery(Query query, {int batchSize = 350}) async {
    while (true) {
      final snapshot = await query.limit(batchSize).get();
      if (snapshot.docs.isEmpty) break;

      final batch = _db.batch();
      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();

      if (snapshot.docs.length < batchSize) break;
    }
  }

  Future<void> _deleteDocumentIfExists(DocumentReference doc) async {
    final snap = await doc.get();
    if (!snap.exists) return;
    await doc.delete();
  }

  Future<void> clearSessionRuntimeData({
    required String raceId,
    required String sessionId,
    String? eventId,
  }) async {
    try {
      final callable =
          FirebaseFunctions.instance.httpsCallable('clearSessionRuntimeData');
      await callable.call({
        'raceId': raceId,
        'sessionId': sessionId,
        'eventId': eventId,
      });
      return;
    } catch (e) {
      // Fallback for local/dev flows where callable may be unavailable.
      _debugLog('clearSessionRuntimeData callable failed, fallback local: $e');
    }

    final useEventPath = eventId != null && eventId.isNotEmpty;

    if (useEventPath) {
      final eventSessionRef = _db
          .collection('events')
          .doc(eventId)
          .collection('sessions')
          .doc(sessionId);

      final eventParticipantsSnap =
          await eventSessionRef.collection('participants').get();
      for (final participantDoc in eventParticipantsSnap.docs) {
        await _deleteCollection(participantDoc.reference.collection('laps'));
        await _deleteCollection(
            participantDoc.reference.collection('crossings'));
        await _deleteCollection(
            participantDoc.reference.collection('analysis'));
        await _deleteCollection(participantDoc.reference.collection('state'));
        await participantDoc.reference.delete();
      }

      await _deleteCollection(eventSessionRef.collection('passings'));
      await _deleteCollection(eventSessionRef.collection('local_lap_closures'));
      await _deleteCollection(eventSessionRef.collection('analysis'));
    }

    // Legacy passings path
    final racePassingsQuery = _db
        .collection('races')
        .doc(raceId)
        .collection('passings')
        .where('session_id', isEqualTo: sessionId);
    await _deleteQuery(racePassingsQuery);

    // Legacy local closures path
    final raceClosuresQuery = _db
        .collection('races')
        .doc(raceId)
        .collection('local_lap_closures')
        .where('session_id', isEqualTo: sessionId);
    await _deleteQuery(raceClosuresQuery);

    // Legacy participant scoped session data
    final raceParticipantsSnap = await _db
        .collection('races')
        .doc(raceId)
        .collection('participants')
        .get();
    for (final participantDoc in raceParticipantsSnap.docs) {
      final sessionRef =
          participantDoc.reference.collection('sessions').doc(sessionId);
      await _deleteCollection(sessionRef.collection('laps'));
      await _deleteCollection(sessionRef.collection('crossings'));
      await _deleteCollection(sessionRef.collection('analysis'));
      await _deleteCollection(sessionRef.collection('state'));
      await _deleteDocumentIfExists(sessionRef);
    }
  }

  // --- Passings ---

  Future<void> addPassing(
    PassingModel passing, {
    String? eventId,
    String? sessionId,
  }) async {
    final payload = passing.toMap();
    final effectiveSessionId = sessionId ?? passing.sessionId;

    await _db
        .collection('races')
        .doc(passing.raceId)
        .collection('passings')
        .add(payload);

    if (eventId != null &&
        eventId.isNotEmpty &&
        effectiveSessionId != null &&
        effectiveSessionId.isNotEmpty) {
      await _db
          .collection('events')
          .doc(eventId)
          .collection('sessions')
          .doc(effectiveSessionId)
          .collection('passings')
          .add({
        ...payload,
        'session_id': effectiveSessionId,
        'event_id': eventId,
      });
    }
  }

  Stream<List<PassingModel>> getPassingsStream(
    String raceId, {
    String? sessionId,
    String? eventId,
    RaceSession? session,
  }) {
    final bool useEventPath = eventId != null &&
        eventId.isNotEmpty &&
        sessionId != null &&
        sessionId.isNotEmpty;
    final baseStream = useEventPath
        ? _db
            .collection('events')
            .doc(eventId)
            .collection('sessions')
            .doc(sessionId)
            .collection('passings')
            .orderBy('timestamp', descending: false)
            .limit(1000)
            .snapshots()
        : _db
            .collection('races')
            .doc(raceId)
            .collection('passings')
            .orderBy('timestamp', descending: false)
            .limit(1000)
            .snapshots();

    return baseStream.map((snapshot) {
      final allPassings = snapshot.docs
          .map((doc) =>
              PassingModel.fromMap(doc.id, doc.data() as Map<String, dynamic>))
          .toList();

      // Normalize ordering in-memory in case Firestore has mixed timestamp types
      // (e.g. int and Timestamp), which can otherwise group by type.
      void sortByTime(List<PassingModel> list) {
        list.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      }

      // Filter by time window if session is provided
      if (session != null && session.actualStartTime != null) {
        final filtered = allPassings.where((p) {
          // Include passings within the session time window
          final passingTime = p.timestamp;
          final startTime = session.actualStartTime!;
          final endTime = session.actualEndTime ??
              DateTime.now().add(
                  const Duration(days: 1)); // If not ended, use future date

          final isInRange = passingTime
                  .isAfter(startTime.subtract(const Duration(seconds: 1))) &&
              passingTime.isBefore(endTime.add(const Duration(seconds: 1)));

          return isInRange;
        }).toList();

        sortByTime(filtered);
        return filtered;
      }

      // Fallback to session ID filtering (for backward compatibility)
      if (!useEventPath && sessionId != null) {
        final filtered =
            allPassings.where((p) => p.sessionId == sessionId).toList();
        sortByTime(filtered);
        return filtered;
      }

      sortByTime(allPassings);
      return allPassings;
    });
  }

  Future<void> updatePassingFlag(
      String raceId, String passingId, String flag, bool add,
      {String? eventId, String? sessionId}) async {
    final useEventPath = eventId != null &&
        eventId.isNotEmpty &&
        sessionId != null &&
        sessionId.isNotEmpty;
    final docRef = useEventPath
        ? _db
            .collection('events')
            .doc(eventId)
            .collection('sessions')
            .doc(sessionId)
            .collection('passings')
            .doc(passingId)
        : _db
            .collection('races')
            .doc(raceId)
            .collection('passings')
            .doc(passingId);

    if (add) {
      await docRef.update({
        'flags': FieldValue.arrayUnion([flag])
      });
    } else {
      await docRef.update({
        'flags': FieldValue.arrayRemove([flag])
      });
    }
  }

  Future<void> archiveCurrentLaps(
    String raceId,
    String uid,
    String sessionId, {
    String? eventId,
  }) async {
    final bool useEventPath =
        eventId != null && eventId.isNotEmpty && sessionId.isNotEmpty;

    final lapsRef = useEventPath
        ? _db
            .collection('events')
            .doc(eventId)
            .collection('sessions')
            .doc(sessionId)
            .collection('participants')
            .doc(uid)
            .collection('laps')
        : _db
            .collection('races')
            .doc(raceId)
            .collection('participants')
            .doc(uid)
            .collection('laps');
    final snapshot = await lapsRef.get();

    if (snapshot.docs.isEmpty) return;

    // Target: .../participants/{uid}/history_sessions/{sessionId}
    final historySessionDocRef = useEventPath
        ? _db
            .collection('events')
            .doc(eventId)
            .collection('sessions')
            .doc(sessionId)
            .collection('participants')
            .doc(uid)
            .collection('history_sessions')
            .doc(sessionId)
        : _db
            .collection('races')
            .doc(raceId)
            .collection('participants')
            .doc(uid)
            .collection('history_sessions')
            .doc(sessionId);

    // Save session metadata
    await historySessionDocRef.set({
      'archived_at': FieldValue.serverTimestamp(),
      'session_id': sessionId,
      'race_id': raceId,
      'event_id': eventId,
    }, SetOptions(merge: true));

    final historyLapsRef = historySessionDocRef.collection('laps');

    final batch = _db.batch();
    for (var doc in snapshot.docs) {
      // Copy to history/session/laps
      batch.set(historyLapsRef.doc(doc.id), doc.data());
      // Delete from current laps
      batch.delete(doc.reference);
    }

    await batch.commit();
  }
}
