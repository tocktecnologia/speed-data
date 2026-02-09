import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:speed_data/features/models/user_role.dart';
import 'package:cloud_functions/cloud_functions.dart';

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

  Stream<QuerySnapshot> getOpenRaces() {
    return _db
        .collection('races')
        .where('status', isEqualTo: 'open')
        // .orderBy('created_at', descending: true) // Commented out to fix potential index issue
        .snapshots();
  }

  Future<void> joinRace(String raceId, String uid, String displayName) async {
    await _db
        .collection('races')
        .doc(raceId)
        .collection('participants')
        .doc(uid)
        .set({
      'uid': uid,
      'display_name': displayName,
      'joined_at': FieldValue.serverTimestamp(),
    });
  }

  Stream<DocumentSnapshot> getRaceStream(String raceId) {
    return _db.collection('races').doc(raceId).snapshots();
  }

  // --- Telemetry ---

  /// Updates the current live location of a pilot in a race
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
      List<Map<String, dynamic>>? checkpoints) async {
    try {
      final callable =
          FirebaseFunctions.instance.httpsCallable('ingestTelemetry');
      await callable.call({
        'raceId': raceId,
        'uid': uid,
        'points': points,
        'checkpoints': checkpoints,
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
}
