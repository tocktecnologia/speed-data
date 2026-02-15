import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:speed_data/features/services/firestore_service.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

class TelemetryService extends ChangeNotifier {
  final FirestoreService _firestoreService = FirestoreService();

  StreamSubscription<Position>? _positionStreamSubscription;
  Timer? _syncTimer;

  bool _enableSendDataToCloud = false; // Default to false, wait for active session
  bool get enableSendDataToCloud => _enableSendDataToCloud;
  set enableSendDataToCloud(bool value) {
    if (_enableSendDataToCloud != value) {
      _enableSendDataToCloud = value;
      notifyListeners();
    }
  }

  void setSessionId(String? id) {
    if (_currentSessionId != id) {
      _currentSessionId = id;
      notifyListeners();
    }
  }

  bool _isRecording = false;
  bool get isRecording => _isRecording;

  Position? _currentPosition;
  Position? get currentPosition => _currentPosition;

  String? _currentRaceId;
  String? _currentUserId;
  String? _currentSessionId;
  String? get currentSessionId => _currentSessionId;
  List<Map<String, dynamic>>? _checkpoints;

  // Buffer for telemetry points (volatile memory)
  final List<Map<String, dynamic>> _buffer = [];

  // Configuration
  static const int _syncIntervalSeconds = 5;
  static const int _samplingIntervalMs = 50;
  // Frequency Tracking
  double _currentFrequency = 0.0;
  double get currentFrequency => _currentFrequency;

  void setCheckpoints(List<Map<String, dynamic>> checkpoints) {
    _checkpoints = checkpoints;
  }

  Future<void> startRecording(String raceId, String userId) async {
    if (_isRecording) return;

    // Enable Wakelock to keep screen on and CPU active
    await WakelockPlus.enable();

    // Generate Session ID (dd-MM-yyyy HH:mm:ss) if not already set
    if (_currentSessionId == null) {
      final now = DateTime.now();
      _currentSessionId = DateFormat('dd-MM-yyyy HH:mm:ss').format(now);
    }

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
    _buffer.clear();
    notifyListeners();

    // Start Location Stream
    late LocationSettings locationSettings;
    if (defaultTargetPlatform == TargetPlatform.android) {
      locationSettings = AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
        forceLocationManager: false, // Fuse Location Provider
        intervalDuration: const Duration(milliseconds: _samplingIntervalMs),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: "Race Recording",
          notificationText: "Telemetry is being captured in background",
          enableWakeLock: true,
        ),
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

    // Start Frequency Timer
    _currentFrequency = 0.0;
  }

  Future<void> stopRecording() async {
    _isRecording = false;
    notifyListeners();

    // Disable WakeLock
    await WakelockPlus.disable();

    _positionStreamSubscription?.cancel();
    _positionStreamSubscription = null;

    _syncTimer?.cancel();
    _syncTimer = null;

    _currentFrequency = 0.0;

    // Final sync of remaining data
    if (_currentRaceId != null && _currentUserId != null) {
      await _syncData();
    }

    _currentRaceId = null;
    _currentUserId = null;
    _currentSessionId = null;
    _buffer.clear();
  }

  Future<void> _handleLocationUpdate(Position position) async {
    if (_currentRaceId == null || _currentUserId == null) return;

    // We capture every point as requested (100ms ideally).
    // No minimum distance filter to ensure raw telemetry for high-speed analysis.

    final point = {
      'raceId': _currentRaceId,
      'uid': _currentUserId,
      'session': _currentSessionId,
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
      if (_enableSendDataToCloud) {
        await _firestoreService.sendTelemetryBatch(_currentRaceId!,
            _currentUserId!, batch, _checkpoints, _currentSessionId!);
      }

      _currentFrequency = batch.length.toDouble() / _syncIntervalSeconds;

      if (kDebugMode) {
        print('Synced telemetry batch: ${batch.length} points');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error syncing telemetry batch: $e');
      }
      // On failure, restore data to the buffer (prepend to keep order roughly,
      // though strictly strictly prepending a block maintains order relative to new data)
      _buffer.insertAll(0, batch);
    }
  }
}
