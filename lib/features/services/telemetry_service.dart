import 'dart:async';
import 'dart:math' as math;
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

  static const double _checkpointDistanceToleranceM = 40.0;
  static const int _dedupWindowMs = 400;
  static const double _defaultTrapWidthM = 50.0;

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

  bool _localTimingEnabled = false;
  bool get localTimingEnabled => _localTimingEnabled;

  int _localTimingMinLapMs = 0;

  List<_LocalTimingLine> _localTimingLines = const [];
  _LocalTimingPoint? _localTimingPreviousPoint;
  bool _localStartFinishSamePoint = false;
  int _localFinishCheckpointIndex = 0;
  int _localCurrentLapNumber = 1;
  int? _localLapStartMs;
  int _localLastCheckpointIndex = -1;
  int? _localLastCrossedAtMs;
  Map<int, int> _localCheckpointTimes = {};
  Map<int, double> _localCheckpointSpeeds = {};
  final List<int> _localCompletedLapTimesMs = [];
  int? _localBestLapMs;
  int? _localPreviousLapMs;

  int get localCurrentLapNumber => _localCurrentLapNumber;
  int? get localLapStartMs => _localLapStartMs;
  int? get localBestLapMs => _localBestLapMs;
  int? get localPreviousLapMs => _localPreviousLapMs;
  List<int> get localCompletedLapTimesMs =>
      List<int>.unmodifiable(_localCompletedLapTimesMs);

  int? get localCurrentLapMs {
    if (_localLapStartMs == null) return null;
    final diff = DateTime.now().millisecondsSinceEpoch - _localLapStartMs!;
    return diff > 0 ? diff : 0;
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
      _resetLocalTimingState(clearHistory: true, clearPrevPoint: true);
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
    _rebuildLocalTimingGeometry();
  }

  void setTimelines(List<Map<String, dynamic>> timelines) {
    _timelines = timelines;
    _rebuildLocalTimingGeometry();
  }

  void setLocalTimingEnabled(bool enabled) {
    if (_localTimingEnabled == enabled) return;
    _localTimingEnabled = enabled;
    _resetLocalTimingState(clearHistory: true, clearPrevPoint: true);
    _rebuildLocalTimingGeometry();
    notifyListeners();
  }

  void setLocalTimingMinLapSeconds(int seconds) {
    _localTimingMinLapMs = math.max(0, seconds) * 1000;
  }

  void _resetLocalTimingState({
    bool clearHistory = false,
    bool clearPrevPoint = false,
  }) {
    _localCurrentLapNumber = 1;
    _localLapStartMs = null;
    _localLastCheckpointIndex = -1;
    _localLastCrossedAtMs = null;
    _localCheckpointTimes = {};
    _localCheckpointSpeeds = {};
    if (clearHistory) {
      _localCompletedLapTimesMs.clear();
      _localBestLapMs = null;
      _localPreviousLapMs = null;
    }
    if (clearPrevPoint) {
      _localTimingPreviousPoint = null;
    }
  }

  void _rebuildLocalTimingGeometry() {
    if (!_localTimingEnabled) {
      _localTimingLines = const [];
      return;
    }
    final effectiveCheckpoints = _resolveEffectiveCheckpoints(
      _checkpoints,
      _timelines,
    );
    _localTimingLines = _buildTimingLines(
      effectiveCheckpoints,
      trapWidthM: _defaultTrapWidthM,
    );
    _localFinishCheckpointIndex =
        _localTimingLines.isEmpty ? 0 : (_localTimingLines.length - 1);
    if (_localTimingLines.length >= 2) {
      final first = _localTimingLines.first.center;
      final last = _localTimingLines.last.center;
      _localStartFinishSamePoint = Geolocator.distanceBetween(
            first.latitude,
            first.longitude,
            last.latitude,
            last.longitude,
          ) <=
          _checkpointDistanceToleranceM;
    } else {
      _localStartFinishSamePoint = false;
    }
  }

  List<LatLng> _resolveEffectiveCheckpoints(
    List<Map<String, dynamic>>? rawCheckpoints,
    List<Map<String, dynamic>>? rawTimelines,
  ) {
    final checkpoints = <LatLng>[];
    if (rawCheckpoints != null) {
      for (final raw in rawCheckpoints) {
        final lat = raw['lat'];
        final lng = raw['lng'];
        if (lat is num && lng is num) {
          checkpoints.add(LatLng(lat.toDouble(), lng.toDouble()));
        }
      }
    }
    if (checkpoints.length < 2) return checkpoints;

    final timelines = <_LocalTimelineRef>[];
    if (rawTimelines != null) {
      for (int i = 0; i < rawTimelines.length; i++) {
        final raw = rawTimelines[i];
        final checkpointIndexRaw = raw['checkpoint_index'] ??
            raw['checkpointIndex'] ??
            raw['checkpoint'];
        final checkpointIndex = _asInt(checkpointIndexRaw);
        if (checkpointIndex == null) continue;
        final order = _asInt(raw['order']) ?? i;
        final enabled = raw['enabled'] != false;
        if (!enabled) continue;
        final typeRaw = '${raw['type'] ?? ''}'.trim().toLowerCase();
        String type = 'split';
        if (typeRaw == 'start_finish' ||
            typeRaw == 'startfinish' ||
            typeRaw == 'start-finish' ||
            typeRaw == 'sf') {
          type = 'start_finish';
        } else if (typeRaw == 'trap') {
          type = 'trap';
        }
        timelines.add(
          _LocalTimelineRef(
            type: type,
            checkpointIndex: checkpointIndex,
            order: order,
          ),
        );
      }
    }

    if (timelines.isEmpty) return checkpoints;
    timelines.sort((a, b) => a.order.compareTo(b.order));

    final startTimeline = timelines.cast<_LocalTimelineRef?>().firstWhere(
          (t) => t?.type == 'start_finish',
          orElse: () => null,
        );

    final startIdx = startTimeline != null &&
            startTimeline.checkpointIndex >= 0 &&
            startTimeline.checkpointIndex < checkpoints.length
        ? startTimeline.checkpointIndex
        : 0;

    final originalFinishIdx = checkpoints.length - 1;
    final originalStart = checkpoints.first;
    final originalFinish = checkpoints.last;
    final trackIsClosed = Geolocator.distanceBetween(
          originalStart.latitude,
          originalStart.longitude,
          originalFinish.latitude,
          originalFinish.longitude,
        ) <=
        _checkpointDistanceToleranceM;
    final finishIdx = trackIsClosed ? startIdx : originalFinishIdx;

    final usedIndices = <int>{startIdx, finishIdx};
    final intermediate = <LatLng>[];
    for (final timeline in timelines) {
      if (timeline.type == 'start_finish') continue;
      final idx = timeline.checkpointIndex;
      if (idx < 0 || idx >= checkpoints.length) continue;
      if (usedIndices.contains(idx)) continue;
      usedIndices.add(idx);
      intermediate.add(checkpoints[idx]);
    }

    if (intermediate.isEmpty &&
        startIdx == 0 &&
        finishIdx == originalFinishIdx) {
      for (int i = 1; i < originalFinishIdx; i++) {
        intermediate.add(checkpoints[i]);
      }
    }

    final effective = <LatLng>[
      checkpoints[startIdx],
      ...intermediate,
      checkpoints[finishIdx],
    ];

    return effective.length < 2 ? checkpoints : effective;
  }

  List<_LocalTimingLine> _buildTimingLines(
    List<LatLng> checkpoints, {
    required double trapWidthM,
  }) {
    if (checkpoints.length < 2) return const [];
    final lines = <_LocalTimingLine>[];
    for (int i = 0; i < checkpoints.length; i++) {
      final center = checkpoints[i];
      final prev = i > 0 ? checkpoints[i - 1] : checkpoints[i];
      final next =
          i < checkpoints.length - 1 ? checkpoints[i + 1] : checkpoints[i];
      final prevLocal = _pointToLocalMeters(prev, center);
      final nextLocal = _pointToLocalMeters(next, center);
      final tangent = _Vec2(
        x: nextLocal.x - prevLocal.x,
        y: nextLocal.y - prevLocal.y,
      );

      _Vec2? normalUnit = _normalizeVec2(tangent);
      normalUnit ??= const _Vec2(x: 1, y: 0);
      final lineUnit = _Vec2(x: -normalUnit.y, y: normalUnit.x);
      lines.add(
        _LocalTimingLine(
          index: i,
          center: center,
          normalUnit: normalUnit,
          lineUnit: lineUnit,
          halfWidthM: math.max(1, trapWidthM) / 2,
        ),
      );
    }
    return lines;
  }

  int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  _Vec2 _metersPerDegree(double latDeg) {
    final latRad = latDeg * (math.pi / 180.0);
    return _Vec2(
      x: 111412.84 * math.cos(latRad), // lng
      y: 111132.92, // lat
    );
  }

  _Vec2 _pointToLocalMeters(LatLng point, LatLng center) {
    final m = _metersPerDegree(center.latitude);
    return _Vec2(
      x: (point.longitude - center.longitude) * m.x,
      y: (point.latitude - center.latitude) * m.y,
    );
  }

  _Vec2? _normalizeVec2(_Vec2 v) {
    final len = math.sqrt(v.x * v.x + v.y * v.y);
    if (len <= 1e-6) return null;
    return _Vec2(x: v.x / len, y: v.y / len);
  }

  double _dot(_Vec2 a, _Vec2 b) => a.x * b.x + a.y * b.y;

  _LocalTimingPoint? _interpolateLineCrossing(
    _LocalTimingLine line,
    _LocalTimingPoint a,
    _LocalTimingPoint b,
  ) {
    final localA = _pointToLocalMeters(LatLng(a.lat, a.lng), line.center);
    final localB = _pointToLocalMeters(LatLng(b.lat, b.lng), line.center);
    final signedA = _dot(localA, line.normalUnit);
    final signedB = _dot(localB, line.normalUnit);
    const eps = 1e-9;
    final bothOnLine = signedA.abs() <= eps && signedB.abs() <= eps;
    if (bothOnLine) return null;
    if (signedA * signedB > 0 && signedA.abs() > eps && signedB.abs() > eps) {
      return null;
    }

    final denom = signedB - signedA;
    if (denom.abs() <= eps) return null;
    final alpha = -signedA / denom;
    if (!alpha.isFinite || alpha < 0 || alpha > 1) return null;

    final alongA = _dot(localA, line.lineUnit);
    final alongB = _dot(localB, line.lineUnit);
    final alongCross = alongA + (alongB - alongA) * alpha;
    if (alongCross.abs() > line.halfWidthM) return null;

    double interp(double av, double bv) => av + (bv - av) * alpha;
    final timestamp =
        (a.timestamp + ((b.timestamp - a.timestamp) * alpha)).round();
    return _LocalTimingPoint(
      lat: interp(a.lat, b.lat),
      lng: interp(a.lng, b.lng),
      speed: interp(a.speed, b.speed),
      heading: interp(a.heading, b.heading),
      altitude: interp(a.altitude, b.altitude),
      timestamp: timestamp,
      method: 'line_interpolation',
      lineOffsetM: alongCross,
      distanceToCheckpointM: 0,
      confidence: 0.97,
    );
  }

  bool _shouldSkipLocalCheckpointCrossing({
    required int lastCheckpointIndex,
    required int checkpointIndex,
    required int? lastCrossedAtMs,
    required int crossedAtMs,
    required int finishCheckpointIndex,
  }) {
    final sameCheckpoint = lastCheckpointIndex == checkpointIndex;
    final tooSoon = lastCrossedAtMs != null &&
        crossedAtMs - lastCrossedAtMs < _dedupWindowMs &&
        sameCheckpoint;
    final wrappedStart =
        lastCheckpointIndex == finishCheckpointIndex && checkpointIndex == 0;
    final outOfOrder = !wrappedStart &&
        checkpointIndex != finishCheckpointIndex &&
        lastCheckpointIndex > checkpointIndex;
    return tooSoon || outOfOrder;
  }

  void _processLocalTimingPoint(_LocalTimingPoint currentPoint) {
    if (!_localTimingEnabled) return;
    if (_localTimingLines.length < 2) {
      _localTimingPreviousPoint = currentPoint;
      return;
    }

    final previous = _localTimingPreviousPoint;
    _localTimingPreviousPoint = currentPoint;
    if (previous == null) return;
    if (currentPoint.timestamp <= previous.timestamp) return;

    final candidates = <_LocalTimingCandidate>[];

    for (final line in _localTimingLines) {
      final rawCheckpointIndex = line.index;
      if (rawCheckpointIndex < 0 ||
          rawCheckpointIndex > _localFinishCheckpointIndex) {
        continue;
      }

      if (_localStartFinishSamePoint) {
        if (_localLapStartMs == null &&
            rawCheckpointIndex == _localFinishCheckpointIndex) {
          continue;
        }
        if (_localLapStartMs != null && rawCheckpointIndex == 0) {
          continue;
        }
      }

      _LocalTimingPoint? crossing =
          _interpolateLineCrossing(line, previous, currentPoint);

      if (crossing == null) {
        final distToCheckpoint = Geolocator.distanceBetween(
          line.center.latitude,
          line.center.longitude,
          currentPoint.lat,
          currentPoint.lng,
        );
        if (distToCheckpoint <= _checkpointDistanceToleranceM) {
          bool passesDirectionGate = true;
          if (rawCheckpointIndex != _localFinishCheckpointIndex &&
              rawCheckpointIndex + 1 < _localTimingLines.length) {
            final nextCheckpoint =
                _localTimingLines[rawCheckpointIndex + 1].center;
            final vTrackLat = nextCheckpoint.latitude - line.center.latitude;
            final vTrackLng = nextCheckpoint.longitude - line.center.longitude;
            final vPilotLat = currentPoint.lat - line.center.latitude;
            final vPilotLng = currentPoint.lng - line.center.longitude;
            final dot = vPilotLat * vTrackLat + vPilotLng * vTrackLng;
            final lenSq = vTrackLat * vTrackLat + vTrackLng * vTrackLng;
            if (dot < 0 || dot > lenSq) {
              passesDirectionGate = false;
            }
          }

          if (passesDirectionGate) {
            crossing = _LocalTimingPoint(
              lat: currentPoint.lat,
              lng: currentPoint.lng,
              speed: currentPoint.speed,
              heading: currentPoint.heading,
              altitude: currentPoint.altitude,
              timestamp: currentPoint.timestamp,
              method: 'nearest_point_fallback',
              lineOffsetM: 0,
              distanceToCheckpointM: distToCheckpoint,
              confidence: 0.7,
            );
          }
        }
      }

      if (crossing == null) continue;

      final openingOnSharedLine = _localStartFinishSamePoint &&
          rawCheckpointIndex == _localFinishCheckpointIndex &&
          _localLapStartMs == null;
      final checkpointIndex = openingOnSharedLine ? 0 : rawCheckpointIndex;

      final shouldSkip = _shouldSkipLocalCheckpointCrossing(
        lastCheckpointIndex: _localLastCheckpointIndex,
        checkpointIndex: checkpointIndex,
        lastCrossedAtMs: _localLastCrossedAtMs,
        crossedAtMs: crossing.timestamp,
        finishCheckpointIndex: _localFinishCheckpointIndex,
      );
      if (shouldSkip) continue;

      final ignoreFinishAtLapOpen = _localStartFinishSamePoint &&
          rawCheckpointIndex == _localFinishCheckpointIndex &&
          _localLapStartMs != null &&
          crossing.timestamp - _localLapStartMs! < _localTimingMinLapMs;
      if (ignoreFinishAtLapOpen) continue;

      candidates.add(
        _LocalTimingCandidate(
          crossing: crossing,
          rawCheckpointIndex: rawCheckpointIndex,
          checkpointIndex: checkpointIndex,
          openingOnSharedLine: openingOnSharedLine,
        ),
      );
    }

    if (candidates.isEmpty) return;
    candidates.sort((a, b) {
      if (a.crossing.timestamp != b.crossing.timestamp) {
        return a.crossing.timestamp.compareTo(b.crossing.timestamp);
      }
      return a.crossing.lineOffsetM
          .abs()
          .compareTo(b.crossing.lineOffsetM.abs());
    });

    final selected = candidates.first;
    final crossing = selected.crossing;
    final checkpointIndex = selected.checkpointIndex;
    final rawCheckpointIndex = selected.rawCheckpointIndex;
    final openingOnSharedLine = selected.openingOnSharedLine;

    _localLastCheckpointIndex = checkpointIndex;
    _localLastCrossedAtMs = crossing.timestamp;
    _localCheckpointTimes[checkpointIndex] = crossing.timestamp;
    _localCheckpointSpeeds[checkpointIndex] = crossing.speed;

    if (checkpointIndex == 0 && _localLapStartMs == null) {
      _localLapStartMs = crossing.timestamp;
    }

    if (rawCheckpointIndex == _localFinishCheckpointIndex &&
        _localLapStartMs != null &&
        !openingOnSharedLine) {
      final lapEnd = crossing.timestamp;
      final lapTime = lapEnd - _localLapStartMs!;
      if (lapTime > 0 && lapTime >= _localTimingMinLapMs) {
        _localCompletedLapTimesMs.add(lapTime);
        _localPreviousLapMs = lapTime;
        if (_localBestLapMs == null || lapTime < _localBestLapMs!) {
          _localBestLapMs = lapTime;
        }
      }

      final nextLap = _localCurrentLapNumber + 1;
      if (_localStartFinishSamePoint) {
        _localCurrentLapNumber = nextLap;
        _localLapStartMs = lapEnd;
        _localLastCheckpointIndex = 0;
        _localLastCrossedAtMs = lapEnd;
        _localCheckpointTimes = {0: lapEnd};
        _localCheckpointSpeeds = {0: crossing.speed};
      } else {
        _localCurrentLapNumber = nextLap;
        _localLapStartMs = null;
        _localLastCheckpointIndex = _localFinishCheckpointIndex;
        _localLastCrossedAtMs = lapEnd;
        _localCheckpointTimes = {};
        _localCheckpointSpeeds = {};
      }
    }

    notifyListeners();
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
    _resetLocalTimingState(clearHistory: true, clearPrevPoint: true);

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
    _resetLocalTimingState(clearHistory: true, clearPrevPoint: true);
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

    final timestamp = position.timestamp.millisecondsSinceEpoch;
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
      'timestamp': timestamp,
    };

    _processLocalTimingPoint(
      _LocalTimingPoint(
        lat: position.latitude,
        lng: position.longitude,
        speed: position.speed,
        heading: position.heading,
        altitude: position.altitude,
        timestamp: timestamp,
      ),
    );

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
    _processLocalTimingPoint(
      _LocalTimingPoint(
        lat: newPos.latitude,
        lng: newPos.longitude,
        speed: _simulationSpeed,
        heading: 0,
        altitude: 0,
        timestamp: point['timestamp'] as int,
      ),
    );
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

class _Vec2 {
  final double x;
  final double y;

  const _Vec2({required this.x, required this.y});
}

class _LocalTimelineRef {
  final String type;
  final int checkpointIndex;
  final int order;

  const _LocalTimelineRef({
    required this.type,
    required this.checkpointIndex,
    required this.order,
  });
}

class _LocalTimingLine {
  final int index;
  final LatLng center;
  final _Vec2 normalUnit;
  final _Vec2 lineUnit;
  final double halfWidthM;

  const _LocalTimingLine({
    required this.index,
    required this.center,
    required this.normalUnit,
    required this.lineUnit,
    required this.halfWidthM,
  });
}

class _LocalTimingPoint {
  final double lat;
  final double lng;
  final double speed;
  final double heading;
  final double altitude;
  final int timestamp;
  final String method;
  final double lineOffsetM;
  final double distanceToCheckpointM;
  final double confidence;

  const _LocalTimingPoint({
    required this.lat,
    required this.lng,
    required this.speed,
    required this.heading,
    required this.altitude,
    required this.timestamp,
    this.method = 'sample',
    this.lineOffsetM = 0,
    this.distanceToCheckpointM = 0,
    this.confidence = 0,
  });
}

class _LocalTimingCandidate {
  final _LocalTimingPoint crossing;
  final int rawCheckpointIndex;
  final int checkpointIndex;
  final bool openingOnSharedLine;

  const _LocalTimingCandidate({
    required this.crossing,
    required this.rawCheckpointIndex,
    required this.checkpointIndex,
    required this.openingOnSharedLine,
  });
}
