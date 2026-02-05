import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:speed_data/features/services/firestore_service.dart';

class TelemetryService extends ChangeNotifier {
  final FirestoreService _firestoreService = FirestoreService();

  StreamSubscription<Position>? _positionStreamSubscription;
  Timer? _syncTimer;

  bool _isRecording = false;
  bool get isRecording => _isRecording;

  Position? _currentPosition;
  Position? get currentPosition => _currentPosition;

  String? _currentRaceId;

  String? _currentUserId;

  // Buffer for telemetry points (volatile memory)
  final List<Map<String, dynamic>> _buffer = [];

  // Configuration
  static const int _syncIntervalSeconds = 10;
  static const int _samplingIntervalMs = 100;

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
    _buffer.clear(); // Start fresh
    notifyListeners();

    // Start Location Stream (Aiming for 10Hz)
    // specific settings for Android/iOS might be needed for true 10Hz,
    // but this requests the best possible.
    late LocationSettings locationSettings;
    if (defaultTargetPlatform == TargetPlatform.android) {
      locationSettings = AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
        forceLocationManager: true,
        intervalDuration: const Duration(milliseconds: _samplingIntervalMs),
        // foregroundNotificationConfig: ... // Consider if background is needed
      );
    } else if (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      locationSettings = AppleSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        activityType: ActivityType.fitness,
        distanceFilter: 0,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: true,
      );
    } else {
      locationSettings = const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
      );
    }

    _positionStreamSubscription =
        Geolocator.getPositionStream(locationSettings: locationSettings)
            .listen((Position position) {
      _currentPosition = position;
      notifyListeners();
      _handleLocationUpdate(position);
    });

    // Start Sync Timer
    _syncTimer =
        Timer.periodic(const Duration(seconds: _syncIntervalSeconds), (timer) {
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

    // Final sync of remaining data
    if (_currentRaceId != null && _currentUserId != null) {
      await _syncData();
    }

    _currentRaceId = null;
    _currentUserId = null;
    _buffer.clear();
  }

  Future<void> _handleLocationUpdate(Position position) async {
    if (_currentRaceId == null || _currentUserId == null) return;

    // We capture every point as requested (100ms ideally).
    // No minimum distance filter to ensure raw telemetry for high-speed analysis.

    final point = {
      'raceId': _currentRaceId,
      'uid': _currentUserId,
      'lat': position.latitude,
      'lng': position.longitude,
      'speed': position.speed, // in m/s
      'heading': position.heading,
      'altitude': position.altitude,
      'timestamp': position.timestamp.millisecondsSinceEpoch,
    };

    _buffer.add(point);
  }

  Future<void> _syncData() async {
    if (_currentRaceId == null || _currentUserId == null) return;
    if (_buffer.isEmpty) return;

    // Snapshot buffer and clear main buffer to allow new writes
    final batch = List<Map<String, dynamic>>.from(_buffer);
    _buffer.clear();

    try {
      // 1. Send Batch to Cloud Function
      await _firestoreService.sendTelemetryBatch(
          _currentRaceId!, _currentUserId!, batch);

      // Success! Data collected and sent.
    } catch (e) {
      print('Error syncing telemetry batch: $e');
      // On failure, restore data to the buffer (prepend to keep order roughly,
      // though strictly strictly prepending a block maintains order relative to new data)
      _buffer.insertAll(0, batch);
    }
  }
}
