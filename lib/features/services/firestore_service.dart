import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:speed_data/features/models/user_role.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:speed_data/features/models/event_model.dart';
import 'package:speed_data/features/models/race_session_model.dart';
import 'package:speed_data/features/models/competitor_model.dart';
import 'package:speed_data/features/models/passing_model.dart';
import 'package:speed_data/features/screens/admin/widgets/control_flags.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

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

  Future<RaceEvent?> getEvent(String eventId) async {
    try {
      final doc = await _db.collection('events').doc(eventId).get();
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

  // Find an active event (today/future) for a specific track
  Future<RaceEvent?> getActiveEventForTrack(String trackId) async {
    try {
      final now = DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day);

      final snapshot = await _db
          .collection('events')
          .where('track_id', isEqualTo: trackId)
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
          .get();

      if (snapshot.docs.isNotEmpty) {
        // Return the first one or logic to find the 'most active'
        return RaceEvent.fromMap(
            snapshot.docs.first.id, snapshot.docs.first.data());
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

  Future<Map<String, dynamic>?> getRace(String raceId) async {
    final doc = await _db.collection('races').doc(raceId).get();
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
      final uidSnapshot = await _db
          .collection('events')
          .doc(eventId)
          .collection('competitors')
          .where('uid', isEqualTo: uid)
          .limit(1)
          .get();
      if (uidSnapshot.docs.isNotEmpty) return true;

      final userIdSnapshot = await _db
          .collection('events')
          .doc(eventId)
          .collection('competitors')
          .where('user_id', isEqualTo: uid)
          .limit(1)
          .get();
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
      String? sessionId) async {
    try {
      final callable =
          FirebaseFunctions.instance.httpsCallable('ingestTelemetry');
      await callable.call({
        'raceId': raceId,
        'uid': uid,
        'points': points,
        'checkpoints': checkpoints,
        'session': sessionId,
      });
    } catch (e) {
      print('Error sending telemetry batch: $e');
      rethrow; // Re-throw to handle in service (e.g. keep in buffer)
    }
  }

  Stream<QuerySnapshot> getRaceLocations(String raceId) {
    // Return stream of participants. Consuming widgets must parse the 'current' map field.
    return _db
        .collection('races')
        .doc(raceId)
        .collection('participants')
        .snapshots();
  }

  Stream<QuerySnapshot> getPilotSessions(String raceId, String uid) {
    return _db
        .collection('races')
        .doc(raceId)
        .collection('participants')
        .doc(uid)
        .collection('sessions')
        .snapshots();
  }

  Stream<QuerySnapshot> getSessionLaps(
      String raceId, String uid, String sessionId) {
    return _db
        .collection('races')
        .doc(raceId)
        .collection('participants')
        .doc(uid)
        .collection('sessions')
        .doc(sessionId)
        .collection('laps')
        .orderBy('number', descending: true)
        .snapshots();
  }

  Stream<QuerySnapshot> getLaps(String raceId, String uid,
      {String? sessionId}) {
    if (sessionId != null) {
      return _db
          .collection('races')
          .doc(raceId)
          .collection('participants')
          .doc(uid)
          .collection('sessions')
          .doc(sessionId)
          .collection('laps')
          .orderBy('number', descending: true)
          .snapshots();
    }
    return _db
        .collection('races')
        .doc(raceId)
        .collection('participants')
        .doc(uid)
        .collection('laps')
        .orderBy('number', descending: true)
        .snapshots();
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

  // --- Passings ---

  Future<void> addPassing(PassingModel passing) async {
    await _db
        .collection('races')
        .doc(passing.raceId)
        .collection('passings')
        .add(passing.toMap());
  }

  Stream<List<PassingModel>> getPassingsStream(String raceId,
      {String? sessionId, RaceSession? session}) {
    return _db
        .collection('races')
        .doc(raceId)
        .collection('passings')
        .orderBy('timestamp', descending: false)
        .limit(1000) // Increase limit since we filter in memory
        .snapshots()
        .map((snapshot) {
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
      if (sessionId != null) {
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
      String raceId, String passingId, String flag, bool add) async {
    final docRef = _db
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
      String raceId, String uid, String sessionId) async {
    final lapsRef = _db
        .collection('races')
        .doc(raceId)
        .collection('participants')
        .doc(uid)
        .collection('laps');
    final snapshot = await lapsRef.get();

    if (snapshot.docs.isEmpty) return;

    // Target: .../participants/{uid}/history_sessions/{sessionId}
    final historySessionDocRef = _db
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
