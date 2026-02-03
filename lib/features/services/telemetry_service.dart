import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:speed_data/features/services/firestore_service.dart';
import 'package:speed_data/features/services/local_database_service.dart';

class TelemetryService extends ChangeNotifier {
  final FirestoreService _firestoreService = FirestoreService();
  final LocalDatabaseService _localDb = LocalDatabaseService();

  StreamSubscription<Position>? _positionStreamSubscription;
  Timer? _syncTimer;

  bool _isRecording = false;
  bool get isRecording => _isRecording;

  Position? _currentPosition;
  Position? get currentPosition => _currentPosition;

  Position? _lastRecordedPosition;

  String? _currentRaceId;
  String? _currentUserId;

  // Configuration
  static const int _syncIntervalSeconds = 5;

  Future<void> startRecording(String raceId, String userId) async {
    if (_isRecording) return;

    // Check permissions
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw Exception('Location permissions are denied');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      throw Exception('Location permissions are permanently denied');
    }

    _currentRaceId = raceId;
    _currentUserId = userId;
    _isRecording = true;
    notifyListeners();

    // Start Location Stream (1Hz approx)
    final locationSettings = LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter:
          0, // Update every change, filtered by time implicitly by stream
    );

    _positionStreamSubscription =
        Geolocator.getPositionStream(locationSettings: locationSettings)
            .listen((Position position) {
      _currentPosition = position;
      notifyListeners();
      _handleLocationUpdate(position);
    });

    // Start Sync Timer (Every 5s)
    _syncTimer =
        Timer.periodic(Duration(seconds: _syncIntervalSeconds), (timer) {
      _syncData();
    });
  }

  Future<void> stopRecording() async {
    _isRecording = false;
    notifyListeners();

    _positionStreamSubscription?.cancel();
    _positionStreamSubscription = null;

    _syncTimer?.cancel();
    _syncTimer = null;

    // Final sync
    if (_currentRaceId != null && _currentUserId != null) {
      await _syncData();
    }

    _currentRaceId = null;
    _currentUserId = null;
  }

  Future<void> _handleLocationUpdate(Position position) async {
    if (_currentRaceId == null || _currentUserId == null) return;

    // Filter stationary points (save battery and DB writes)
    if (_lastRecordedPosition != null) {
      final distance = Geolocator.distanceBetween(
        _lastRecordedPosition!.latitude,
        _lastRecordedPosition!.longitude,
        position.latitude,
        position.longitude,
      );

      // If moved less than 3 meters, ignore this update
      if (distance < 3.0) return;
    }

    _lastRecordedPosition = position;

    final point = {
      'raceId': _currentRaceId,
      'uid': _currentUserId,
      'lat': position.latitude,
      'lng': position.longitude,
      'speed': position.speed, // in m/s
      'heading': position.heading,
      'timestamp': position.timestamp.millisecondsSinceEpoch,
      'synced': 0
    };

    await _localDb.insertPoint(point);
  }

  Future<void> _syncData() async {
    if (_currentRaceId == null || _currentUserId == null) return;

    try {
      final unsynced = await _localDb.getUnsyncedPoints(_currentRaceId!);
      if (unsynced.isEmpty) return;

      // 1. Upload Batch to Logs
      await _firestoreService.uploadTelemetryBatch(
          _currentRaceId!, _currentUserId!, unsynced);

      // 2. Update Live Location (use the last point)
      final lastPoint = unsynced.last;

      // Need to convert DateTime back from int if necessary or just pass directly
      // My Service expects explicit params, I can refactor or parse.
      await _firestoreService.updatePilotLocation(
        raceId: _currentRaceId!,
        uid: _currentUserId!,
        lat: lastPoint['lat'],
        lng: lastPoint['lng'],
        speed: lastPoint['speed'],
        heading: lastPoint['heading'],
        timestamp: DateTime.fromMillisecondsSinceEpoch(lastPoint['timestamp']),
      );

      // 3. Mark as Synced
      final ids = unsynced.map((e) => e['id'] as int).toList();
      await _localDb.markAsSynced(ids);

      // Optional: Clean up synced data to keep DB small?
      // User says "finalize... sync...". implies keeping it until done.
      // We can keep it for now.
    } catch (e) {
      print('Error syncing telemetry: $e');
    }
  }
}
