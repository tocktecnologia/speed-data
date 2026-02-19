import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import 'package:speed_data/features/services/firestore_service.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

class TelemetryService extends ChangeNotifier {
  TelemetryService._internal();
  static final TelemetryService instance = TelemetryService._internal();
  factory TelemetryService() => instance;

  final FirestoreService _firestoreService = FirestoreService();

  StreamSubscription<Position>? _positionStreamSubscription;
  Timer? _syncTimer;

  bool _enableSendDataToCloud =
      false; // Default to false, wait for active session
  bool get enableSendDataToCloud => _enableSendDataToCloud;
  set enableSendDataToCloud(bool value) {
    if (_enableSendDataToCloud != value) {
      _enableSendDataToCloud = value;
      notifyListeners();
    }
  }

  bool _simulationOverride = false;
  bool get simulationOverride => _simulationOverride;
  set simulationOverride(bool value) {
    if (_simulationOverride != value) {
      _simulationOverride = value;
      notifyListeners();
    }
  }

  // Simulation state
  bool _isSimulating = false;
  bool get isSimulating => _isSimulating;
  double _simulationSpeed = 40.0; // m/s
  double get simulationSpeed => _simulationSpeed;
  LatLng? _simulatedPosition;
  LatLng? get simulatedPosition => _simulatedPosition;
  Timer? _simulationTimer;
  Timer? _simulationSyncTimer;
  List<Map<String, dynamic>> _simulationBuffer = [];
  double _currentRouteDistance = 0.0;
  List<LatLng> _simulationRoutePath = [];
  List<Map<String, dynamic>> _simulationCheckpoints = [];
  List<Map<String, dynamic>> _simulationTimelines = [];
  static const int _simUpdatesPerSecond = 5;
  static const int _simSyncIntervalSeconds = 5;

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
  String? get currentRaceId => _currentRaceId;
  String? _currentEventId;
  String? get currentEventId => _currentEventId;
  String? _currentUserId;
  String? get currentUserId => _currentUserId;
  String? _currentSessionId;
  String? get currentSessionId => _currentSessionId;
  List<Map<String, dynamic>>? _checkpoints;
  List<Map<String, dynamic>>? _timelines;

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

  void setTimelines(List<Map<String, dynamic>> timelines) {
    _timelines = timelines;
  }

  void setSimulationSpeed(double value) {
    if (value == _simulationSpeed) return;
    _simulationSpeed = value;
    notifyListeners();
  }

  Future<void> startSimulation({
    required List<LatLng> routePath,
    required List<Map<String, dynamic>> checkpoints,
    required String raceId,
    required String userId,
    required String sessionId,
    String? eventId,
    double? initialSpeed,
    List<Map<String, dynamic>>? timelines,
  }) async {
    if (routePath.isEmpty) return;
    if (_isSimulating) return;

    if (initialSpeed != null) {
      _simulationSpeed = initialSpeed;
    }

    _simulationRoutePath = routePath;
    _simulationCheckpoints = checkpoints;
    _simulationTimelines = timelines ?? [];

    await stopRecording();

    _currentRaceId = raceId;
    _currentEventId = eventId;
    _currentUserId = userId;
    setSessionId(sessionId);

    final totalLength = _calculatePathLength(_simulationRoutePath);
    double initialDistance = 0.0;
    if (totalLength > 50) {
      initialDistance = totalLength - 50;
    }

    _isSimulating = true;
    _currentRouteDistance = initialDistance;
    _simulatedPosition =
        _getPointAtDistance(initialDistance, _simulationRoutePath);
    notifyListeners();

    _simulationBuffer.clear();
    simulationOverride = true;
    enableSendDataToCloud = false;

    _simulationSyncTimer =
        Timer.periodic(const Duration(seconds: _simSyncIntervalSeconds), (_) {
      _syncSimulationData();
    });

    final int intervalMs = (1000 / _simUpdatesPerSecond).round();
    _simulationTimer =
        Timer.periodic(Duration(milliseconds: intervalMs), (timer) {
      _simulateTick(intervalMs / 1000.0);
    });
  }

  Future<void> stopSimulation() async {
    _simulationTimer?.cancel();
    _simulationTimer = null;
    _simulationSyncTimer?.cancel();
    _simulationSyncTimer = null;
    await _syncSimulationData();

    _isSimulating = false;
    _simulatedPosition = null;
    _simulationTimelines = [];
    notifyListeners();

    simulationOverride = false;

    if (_currentRaceId != null &&
        _currentUserId != null &&
        _currentSessionId != null) {
      enableSendDataToCloud = true;
      await startRecording(
        _currentRaceId!,
        _currentUserId!,
        eventId: _currentEventId,
        sessionId: _currentSessionId,
      );
    }
  }

  Future<void> startRecording(
    String raceId,
    String userId, {
    String? eventId,
    String? sessionId,
  }) async {
    if (_isRecording) {
      if (_currentRaceId == raceId && _currentUserId == userId) return;
      await stopRecording();
    }

    // Enable Wakelock to keep screen on and CPU active
    await WakelockPlus.enable();

    if (sessionId != null && sessionId.isNotEmpty) {
      _currentSessionId = sessionId;
    }

    // Generate Session ID (dd-MM-yyyy HH:mm:ss) if not already set
    if (_currentSessionId == null || _currentSessionId!.isEmpty) {
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
    _currentEventId = eventId;
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
    _currentEventId = null;
    _currentUserId = null;
    _currentSessionId = null;
    _buffer.clear();
    _timelines = null;
  }

  Future<void> _handleLocationUpdate(Position position) async {
    if (_currentRaceId == null || _currentUserId == null) return;

    // We capture every point as requested (100ms ideally).
    // No minimum distance filter to ensure raw telemetry for high-speed analysis.

    final point = {
      'raceId': _currentRaceId,
      'eventId': _currentEventId,
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

  void _simulateTick(double dt) {
    final stepDistance = _simulationSpeed * dt;
    _currentRouteDistance += stepDistance;

    final totalLength = _calculatePathLength(_simulationRoutePath);
    if (_currentRouteDistance >= totalLength) {
      _currentRouteDistance = 0;
    }

    final newPos =
        _getPointAtDistance(_currentRouteDistance, _simulationRoutePath);
    _simulatedPosition = newPos;
    notifyListeners();

    final point = {
      'raceId': _currentRaceId,
      'eventId': _currentEventId,
      'uid': _currentUserId,
      'session': _currentSessionId,
      'lat': newPos.latitude,
      'lng': newPos.longitude,
      'speed': _simulationSpeed,
      'heading': 0.0,
      'altitude': 0.0,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
    _simulationBuffer.add(point);
  }

  Future<void> _syncSimulationData() async {
    if (_simulationBuffer.isEmpty) return;
    if (_currentRaceId == null || _currentUserId == null) return;
    if (_currentSessionId == null || _currentSessionId!.isEmpty) return;

    final batch = List<Map<String, dynamic>>.from(_simulationBuffer);
    _simulationBuffer.clear();

    try {
      await _firestoreService.sendTelemetryBatch(
        _currentRaceId!,
        _currentUserId!,
        batch,
        _simulationCheckpoints,
        _currentSessionId!,
        eventId: _currentEventId,
        timelines: _simulationTimelines,
      );
    } catch (e) {
      _simulationBuffer.insertAll(0, batch);
    }
  }

  double _calculatePathLength(List<LatLng> path) {
    double dist = 0.0;
    for (int i = 0; i < path.length - 1; i++) {
      dist += Geolocator.distanceBetween(path[i].latitude, path[i].longitude,
          path[i + 1].latitude, path[i + 1].longitude);
    }
    return dist;
  }

  LatLng _getPointAtDistance(double targetDist, List<LatLng> path) {
    if (path.isEmpty) return const LatLng(0, 0);
    if (targetDist <= 0) return path.first;

    double accDist = 0.0;
    for (int i = 0; i < path.length - 1; i++) {
      final start = path[i];
      final end = path[i + 1];
      final segmentDist = Geolocator.distanceBetween(
          start.latitude, start.longitude, end.latitude, end.longitude);

      if (accDist + segmentDist >= targetDist) {
        final remaining = targetDist - accDist;
        final fraction = remaining / segmentDist;
        final lat = start.latitude + (end.latitude - start.latitude) * fraction;
        final lng =
            start.longitude + (end.longitude - start.longitude) * fraction;
        return LatLng(lat, lng);
      }
      accDist += segmentDist;
    }
    return path.last;
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
        await _firestoreService.sendTelemetryBatch(
          _currentRaceId!,
          _currentUserId!,
          batch,
          _checkpoints,
          _currentSessionId!,
          eventId: _currentEventId,
          timelines: _timelines,
        );
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
