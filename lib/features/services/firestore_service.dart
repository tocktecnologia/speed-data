import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:speed_data/features/models/user_role.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:speed_data/features/models/event_model.dart';
import 'package:speed_data/features/models/race_session_model.dart';
import 'package:speed_data/features/models/competitor_model.dart';

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

  Future<void> setUserRole(String uid, UserRole role) async {
    await _db.collection('users').doc(uid).set({
      'role': role.toStringValue(),
    }, SetOptions(merge: true));
  }

  Future<void> updatePilotProfile(String uid, String name, int color) async {
    await _db.collection('users').doc(uid).set({
      'name': name,
      'color': color,
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

    return query
        .orderBy('date', descending: false)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => RaceEvent.fromMap(doc.id, doc.data() as Map<String, dynamic>))
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

  Stream<QuerySnapshot> getLaps(String raceId, String uid) {
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
