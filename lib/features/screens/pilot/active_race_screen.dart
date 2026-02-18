import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:speed_data/features/services/telemetry_service.dart';
import 'package:speed_data/features/services/firestore_service.dart';
import 'package:speed_data/features/models/competitor_model.dart';
import 'package:speed_data/features/models/event_model.dart';
import 'package:speed_data/features/models/passing_model.dart';
import 'package:speed_data/features/models/race_session_model.dart';
import 'package:speed_data/utils/map_utils.dart';
import 'package:speed_data/features/widgets/track_shape_widget.dart';
import 'package:speed_data/theme/speed_data_theme.dart';

class ActiveRaceScreen extends StatefulWidget {
  final String raceId;
  final String userId;
  final String raceName;
  final String? eventId;

  const ActiveRaceScreen({
    Key? key,
    required this.raceId,
    required this.userId,
    required this.raceName,
    this.eventId,
  }) : super(key: key);

  @override
  State<ActiveRaceScreen> createState() => _ActiveRaceScreenState();
}

enum LiveTimerMode { simple, classic, gauge }

enum GaugeType { speed, gps }

class _ActiveRaceScreenState extends State<ActiveRaceScreen> {
  bool _autoSimulationMode = false;
  bool _simulationConfigLoaded = false;
  GoogleMapController? _mapController;
  final FirestoreService _firestoreService = FirestoreService();
  late TelemetryService _telemetryService;
  Set<Marker> _raceMarkers = {};
  bool _isInitLocationSet = false;

  LatLng? _startLocation;
  Set<Polyline> _polylines = {};
  List<LatLng> _routePath = [];
  List<Map<String, dynamic>> _checkpoints = [];
  Color _userColor = Colors.blue; // Default

  // Auto-sync & Flag state
  String? _currentEventId;
  RaceSession? _activeSession;
  StreamSubscription? _statusSubscription;
  Color _sessionBackgroundColor = Colors.black;
  LiveTimerMode _mode = LiveTimerMode.simple;
  GaugeType _gaugeType = GaugeType.speed;
  Timer? _uiTimer;
  DateTime _uiNow = DateTime.now();
  String? _autoStartedSimulationSessionId;
  int? _localLapStartMs;
  String? _pilotCompetitorId;
  String? _pilotCarNumber;
  String? _pilotDriverName;

  String get _effectiveUserId {
    final authUid = FirebaseAuth.instance.currentUser?.uid;
    if (authUid != null && authUid.isNotEmpty) return authUid;
    return widget.userId;
  }

  @override
  void initState() {
    super.initState();
    _telemetryService = TelemetryService.instance;

    _loadSimulationModeConfig();
    _loadRaceDetails();
    _startUiTimer();
  }

  @override
  void dispose() {
    _statusSubscription?.cancel(); // Cancel subscription on dispose
    _uiTimer?.cancel();
    super.dispose();
  }

  void _startUiTimer() {
    _uiTimer?.cancel();
    _uiTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!mounted) return;
      setState(() {
        _uiNow = DateTime.now();
      });
    });
  }

  Future<void> _loadRaceDetails() async {
    final stream = _firestoreService.getRaceStream(widget.raceId);
    late Future<void> Function() recoverActiveSessionBinding;

    Future<void> attachEventListeners(String eventId) async {
      if (!mounted) return;
      setState(() => _currentEventId = eventId);
      await _loadPilotIdentityForEvent(eventId);

      // Preload current event state to avoid long "waiting active session" gaps
      // when entering/re-entering this screen on slower mobile links.
      try {
        final RaceEvent? event =
            await _firestoreService.getEvent(eventId, forceServer: true);
        if (event != null) {
          RaceSession? preloadedSession;
          try {
            preloadedSession = event.sessions.firstWhere(
              (s) => s.status == SessionStatus.active,
            );
          } catch (_) {
            preloadedSession = null;
          }
          await _applySessionState(preloadedSession);
        }
      } catch (_) {}

      _statusSubscription?.cancel();
      _statusSubscription = _firestoreService
          .getEventActiveSessionStream(eventId)
          .listen((session) async {
        await _applySessionState(session);
        if (session == null) {
          unawaited(recoverActiveSessionBinding());
        }
      });
    }

    recoverActiveSessionBinding = () async {
      await Future.delayed(const Duration(seconds: 2));
      if (!mounted || _activeSession != null) return;

      try {
        final event = await _firestoreService.getActiveEventForTrack(
          widget.raceId,
          allowFallback: true,
          requireActiveSession: true,
          forceServer: true,
        );
        if (!mounted || event == null) return;

        if (_currentEventId != event.id) {
          await attachEventListeners(event.id);
          return;
        }

        try {
          final session = event.sessions
              .firstWhere((s) => s.status == SessionStatus.active);
          await _applySessionState(session);
        } catch (_) {}
      } catch (_) {}
    };

    if (widget.eventId != null && widget.eventId!.isNotEmpty) {
      await attachEventListeners(widget.eventId!);
      unawaited(recoverActiveSessionBinding());
    } else {
      _firestoreService
          .getActiveEventForTrack(
        widget.raceId,
        allowFallback: true,
        requireActiveSession: false,
      )
          .then((event) {
        if (event == null) {
          _applySessionState(null);
          return;
        }
        attachEventListeners(event.id);
        unawaited(recoverActiveSessionBinding());
      }).catchError((_) {});
    }

    final snapshot = await stream.first;

    // Fetch user color
    try {
      final userProfile =
          await _firestoreService.getUserProfile(_effectiveUserId);
      if (userProfile != null && userProfile.containsKey('color')) {
        final colorData = userProfile['color'];
        if (colorData is int) {
          _userColor = Color(colorData);
        } else if (colorData is String) {
          final parsed = int.tryParse(colorData);
          if (parsed != null) {
            _userColor = Color(parsed);
          }
        }
      }
    } catch (e) {
      print('Error fetching user color: $e');
    }

    if (snapshot.exists) {
      final data = snapshot.data() as Map<String, dynamic>;
      final checkpoints = data['checkpoints'] as List<dynamic>?;

      if (checkpoints != null) {
        final markers = <Marker>{};
        final straightRoutePoints = <LatLng>[];
        _checkpoints = checkpoints
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();

        if (checkpoints.isNotEmpty) {
          // Pass checkpoints to telemetry service for cloud function processing
          _telemetryService.setCheckpoints(_checkpoints);

          final firstPoint = checkpoints[0];
          final fLat = (firstPoint['lat'] as num).toDouble();
          final fLng = (firstPoint['lng'] as num).toDouble();
          _startLocation = LatLng(fLat, fLng);

          if (_mapController != null && mounted) {
            _mapController!
                .animateCamera(CameraUpdate.newLatLngZoom(_startLocation!, 16));
            _isInitLocationSet = true;
          }
        }

        // Build Markers
        for (int i = 0; i < checkpoints.length; i++) {
          final point = checkpoints[i];
          final lat = (point['lat'] as num).toDouble();
          final lng = (point['lng'] as num).toDouble();

          // Skip drawing the last marker if it is identical to the first one (closed loop)
          if (i == checkpoints.length - 1 && checkpoints.length > 1) {
            final first = checkpoints[0];
            final fLat = (first['lat'] as num).toDouble();
            final fLng = (first['lng'] as num).toDouble();
            if ((lat - fLat).abs() < 0.000001 &&
                (lng - fLng).abs() < 0.000001) {
              continue;
            }
          }

          final position = LatLng(lat, lng);
          final String label = String.fromCharCode(65 + i);

          straightRoutePoints.add(position);

          final icon = await createCustomMarkerBitmap(label,
              color: i == 0 ? Colors.green : Colors.blue);

          markers.add(
            Marker(
              markerId: MarkerId('checkpoint_$i'),
              position: position,
              infoWindow: InfoWindow(title: 'Checkpoint $label'),
              icon: icon,
            ),
          );
        }

        // Build Polylines
        final polylines = <Polyline>{};
        List<LatLng> finalRoutePoints = straightRoutePoints;

        // Check if we have a detailed street route saved
        final savedRoutePath = data['route_path'] as List<dynamic>?;
        if (savedRoutePath != null && savedRoutePath.isNotEmpty) {
          finalRoutePoints = savedRoutePath.map((p) {
            return LatLng(
                (p['lat'] as num).toDouble(), (p['lng'] as num).toDouble());
          }).toList();
        }

        if (finalRoutePoints.length > 1) {
          polylines.add(
            Polyline(
              polylineId: const PolylineId('race_route'),
              points: finalRoutePoints,
              color: Colors.blue,
              width: 5,
            ),
          );
        }

        if (mounted) {
          setState(() {
            _raceMarkers = markers;
            _polylines = polylines;
            _routePath = finalRoutePoints;
          });
        }
        await _maybeAutoStartSimulation();
      }
    }
  }

  Future<void> _applySessionState(RaceSession? session) async {
    if (!mounted) return;
    final shouldRestartSimulation = session != null &&
        _telemetryService.isSimulating &&
        _telemetryService.currentSessionId != session.id;
    if (shouldRestartSimulation) {
      await _telemetryService.stopSimulation();
      _autoStartedSimulationSessionId = null;
    }

    final previousSessionId = _activeSession?.id;
    setState(() {
      _activeSession = session;
      if (session != null) {
        if (previousSessionId != session.id) {
          _localLapStartMs = _resolveSafeSessionStartMs(session);
        }
        _telemetryService.setSessionId(session.id);
        if (_autoSimulationMode) {
          _telemetryService.enableSendDataToCloud = false;
        } else if (!_telemetryService.isSimulating) {
          _telemetryService.enableSendDataToCloud = true;
          if (!_telemetryService.isRecording) {
            _telemetryService.startRecording(
              widget.raceId,
              _effectiveUserId,
              eventId: _currentEventId,
              sessionId: session.id,
            );
          }
        }
        _sessionBackgroundColor = _getFlagColor(session.currentFlag);
      } else {
        _autoStartedSimulationSessionId = null;
        _localLapStartMs = null;
        _telemetryService.setSessionId(null);
        _telemetryService.enableSendDataToCloud = false;
        _sessionBackgroundColor = Colors.black;
      }
    });
    await _maybeAutoStartSimulation();
  }

  Future<void> _loadSimulationModeConfig() async {
    final email = FirebaseAuth.instance.currentUser?.email;
    final config =
        await _firestoreService.getSimulationRuntimeConfig(email: email);
    if (!mounted) return;

    final enabled = config['enabled'] == true;
    final autoStart = config['auto_start'] != false;
    final speedMps = config['speed_mps'] is num
        ? (config['speed_mps'] as num).toDouble()
        : 40.0;

    setState(() {
      _autoSimulationMode = enabled && autoStart;
      _simulationConfigLoaded = true;
    });
    _telemetryService.setSimulationSpeed(speedMps);

    if (!_autoSimulationMode && _telemetryService.isSimulating) {
      await _telemetryService.stopSimulation();
    }
    await _maybeAutoStartSimulation();
  }

  Future<void> _maybeAutoStartSimulation() async {
    if (!_simulationConfigLoaded || !_autoSimulationMode) return;
    if (_activeSession == null || _activeSession!.id.isEmpty) return;
    if (_routePath.isEmpty) return;
    if (_telemetryService.isSimulating &&
        _telemetryService.currentSessionId != _activeSession!.id) {
      await _telemetryService.stopSimulation();
      _autoStartedSimulationSessionId = null;
    }
    try {
      await _startSimulation(auto: true);
    } catch (_) {}
  }

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
    if (_startLocation != null) {
      _mapController!
          .moveCamera(CameraUpdate.newLatLngZoom(_startLocation!, 16));
      _isInitLocationSet = true;
    }
  }

  Color _getFlagColor(RaceFlag flag) {
    switch (flag) {
      case RaceFlag.green:
        return Colors.green.withOpacity(0.8);
      case RaceFlag.warmup:
        return SpeedDataTheme.flagPurple.withOpacity(0.8);
      case RaceFlag.yellow:
        return Colors.orange.withOpacity(0.8);
      case RaceFlag.red:
        return Colors.red.withOpacity(0.8);
      case RaceFlag.checkered:
        return Colors.white.withOpacity(0.9);
    }
  }

  String _formatLapTime(int ms) {
    final minutes = (ms ~/ 60000).toString().padLeft(2, '0');
    final seconds = ((ms % 60000) ~/ 1000).toString().padLeft(2, '0');
    final milliseconds = (ms % 1000).toString().padLeft(3, '0');
    return '$minutes:$seconds.$milliseconds';
  }

  String _sessionDisplayName(RaceSession session) {
    if (session.name.isNotEmpty) return session.name;
    return session.type.name.toUpperCase();
  }

  Future<void> _loadPilotIdentityForEvent(String eventId) async {
    try {
      final Competitor? competitor =
          await _firestoreService.getCompetitorByUid(eventId, _effectiveUserId);
      if (!mounted) return;
      setState(() {
        _pilotCompetitorId = competitor?.id;
        _pilotCarNumber = competitor?.number.trim();
        _pilotDriverName = competitor?.name.trim();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _pilotCompetitorId = null;
        _pilotCarNumber = null;
        _pilotDriverName = null;
      });
    }
  }

  bool _isCurrentPilotPassing(PassingModel passing) {
    if (passing.participantUid == _effectiveUserId) return true;
    if (_pilotCompetitorId != null &&
        _pilotCompetitorId!.isNotEmpty &&
        passing.participantUid == _pilotCompetitorId) {
      return true;
    }
    if (_pilotCarNumber != null &&
        _pilotCarNumber!.isNotEmpty &&
        passing.carNumber.trim() == _pilotCarNumber) {
      return true;
    }
    if (_pilotDriverName != null &&
        _pilotDriverName!.isNotEmpty &&
        passing.driverName.trim().toLowerCase() ==
            _pilotDriverName!.toLowerCase()) {
      return true;
    }
    return false;
  }

  int? _extractLapStartTimestamp(Map<String, dynamic> lapData) {
    final points = lapData['points'];
    if (points is Map && points['cp_0'] is Map) {
      final cp0 = points['cp_0'] as Map;
      final ts = cp0['timestamp'];
      if (ts is int) return ts;
      if (ts is num) return ts.toInt();
    }
    return null;
  }

  int? _extractLapCloseTimestamp(Map<String, dynamic> lapData) {
    int? readTs(dynamic v) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      return null;
    }

    int? latest;
    final points = lapData['points'];
    if (points is Map) {
      for (final value in points.values) {
        if (value is Map) {
          final ts = readTs(value['timestamp']);
          if (ts != null && (latest == null || ts > latest)) {
            latest = ts;
          }
        }
      }
    } else if (points is List) {
      for (final value in points) {
        if (value is Map) {
          final ts = readTs(value['timestamp']);
          if (ts != null && (latest == null || ts > latest)) {
            latest = ts;
          }
        }
      }
    }

    latest ??= readTs(lapData['end_timestamp']);
    latest ??= readTs(lapData['timestamp']);
    latest ??= readTs(lapData['completed_at']);
    latest ??= readTs(lapData['lap_end_ms']);
    return latest;
  }

  int _resolveSafeSessionStartMs(RaceSession session) {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final startMs = session.actualStartTime?.millisecondsSinceEpoch;
    if (startMs == null) return nowMs;

    final elapsedMs = nowMs - startMs;
    final maxExpectedMs =
        ((session.durationMinutes > 0 ? session.durationMinutes : 30) + 30) *
            60 *
            1000;

    // Ignore stale timestamps that would create an unrealistic running lap.
    if (elapsedMs < 0 || elapsedMs > maxExpectedMs) {
      return nowMs;
    }
    return startMs;
  }

  Future<void> _startSimulation({bool auto = false}) async {
    if (_activeSession == null || _activeSession!.id.isEmpty) {
      if (!auto && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No active session to simulate')));
      }
      return;
    }
    if (_routePath.isEmpty) {
      if (!auto && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No route path available')));
      }
      return;
    }
    if (_telemetryService.isSimulating) {
      if (_telemetryService.currentSessionId == _activeSession!.id) {
        return;
      }
      await _telemetryService.stopSimulation();
      _autoStartedSimulationSessionId = null;
    }
    if (auto && _autoStartedSimulationSessionId == _activeSession!.id) return;
    _autoStartedSimulationSessionId = _activeSession!.id;
    try {
      await _telemetryService.startSimulation(
        routePath: _routePath,
        checkpoints: _checkpoints,
        raceId: widget.raceId,
        userId: _effectiveUserId,
        sessionId: _activeSession!.id,
        eventId: _currentEventId,
      );
    } catch (_) {
      _autoStartedSimulationSessionId = null;
      rethrow;
    }
  }

  Widget _buildModeToggle() {
    Color colorFor(LiveTimerMode mode) =>
        _mode == mode ? Colors.white : Colors.white70;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          tooltip: 'Simple Mode',
          icon: Icon(Icons.timer, color: colorFor(LiveTimerMode.simple)),
          onPressed: () => setState(() => _mode = LiveTimerMode.simple),
        ),
        IconButton(
          tooltip: 'Classic Mode',
          icon: Icon(Icons.map, color: colorFor(LiveTimerMode.classic)),
          onPressed: () => setState(() => _mode = LiveTimerMode.classic),
        ),
        IconButton(
          tooltip: 'Gauge Mode',
          icon: Icon(Icons.speed, color: colorFor(LiveTimerMode.gauge)),
          onPressed: () => setState(() => _mode = LiveTimerMode.gauge),
        ),
      ],
    );
  }

  Widget _buildGauge({
    required String label,
    required double value,
    required double maxValue,
    required Color color,
  }) {
    final normalized = (value / maxValue).clamp(0.0, 1.0);
    return SizedBox(
      width: 220,
      height: 220,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CircularProgressIndicator(
            value: normalized,
            strokeWidth: 16,
            backgroundColor: Colors.white10,
            color: color,
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label.toUpperCase(),
                  style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(
                value.toStringAsFixed(1),
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 40,
                    fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTrackChart({
    required TelemetryService telemetry,
  }) {
    final checkpoints = _checkpoints
        .map((p) => LatLng(
              (p['lat'] as num).toDouble(),
              (p['lng'] as num).toDouble(),
            ))
        .toList();
    final route = _routePath;

    LatLng? pilotPosition;
    if (_telemetryService.isSimulating &&
        _telemetryService.simulatedPosition != null) {
      pilotPosition = _telemetryService.simulatedPosition;
    } else if (telemetry.currentPosition != null) {
      pilotPosition = LatLng(
        telemetry.currentPosition!.latitude,
        telemetry.currentPosition!.longitude,
      );
    }

    final pilots = pilotPosition == null
        ? <PilotPosition>[]
        : [
            PilotPosition(
              uid: _effectiveUserId,
              location: pilotPosition,
              color: _userColor,
              label: 'YOU',
            )
          ];

    return Container(
      color: Colors.black,
      width: double.infinity,
      height: double.infinity,
      padding: const EdgeInsets.all(12),
      child: CustomPaint(
        painter: TrackPainter(
          checkpoints: checkpoints,
          routePath: route,
          pilotPositions: pilots,
        ),
      ),
    );
  }

  Widget _buildSimpleMode({
    required String best,
    required String previous,
    required String current,
  }) {
    Widget row(String title, String value, Color color) {
      return Expanded(
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          color: color,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text(value,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 56,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'monospace')),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        row('Best', best, const Color(0xFF0D2BFF)),
        row('Previous', previous, const Color(0xFF0D2BFF)),
        row('Current', current, const Color(0xFF0D2BFF)),
      ],
    );
  }

  Widget _buildClassicMode({
    required String currentLap,
    required TelemetryService telemetry,
  }) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          width: double.infinity,
          color: Colors.black,
          child: Text(
            currentLap,
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 48,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace'),
          ),
        ),
        Expanded(
          child: _buildTrackChart(telemetry: telemetry),
        ),
      ],
    );
  }

  Widget _buildGaugeMode({
    required String currentLap,
    required TelemetryService telemetry,
  }) {
    final speedKmh = _telemetryService.isSimulating
        ? _telemetryService.simulationSpeed * 3.6
        : (telemetry.currentPosition?.speed ?? 0) * 3.6;
    final gpsHz = telemetry.currentFrequency;
    final isSpeed = _gaugeType == GaugeType.speed;
    final gaugeValue = isSpeed ? speedKmh : gpsHz;
    final gaugeLabel = isSpeed ? 'Speed (km/h)' : 'GPS (Hz)';
    final gaugeMax = isSpeed ? 200.0 : 5.0;

    return Column(
      children: [
        const SizedBox(height: 12),
        GestureDetector(
          onTap: () => setState(() {
            _gaugeType = isSpeed ? GaugeType.gps : GaugeType.speed;
          }),
          child: _buildGauge(
            label: gaugeLabel,
            value: gaugeValue,
            maxValue: gaugeMax,
            color: Colors.greenAccent,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          currentLap,
          style: const TextStyle(
              color: Colors.white,
              fontSize: 40,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _telemetryService,
      child: Scaffold(
        backgroundColor: _sessionBackgroundColor,
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Live Timer${_activeSession != null ? ' - ${_sessionDisplayName(_activeSession!)}' : ''}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                widget.raceName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: Colors.white70),
              ),
            ],
          ),
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
        ),
        body: Consumer<TelemetryService>(
          builder: (context, telemetry, child) {
            // Auto-center map on first valid location update if not done yet
            if (telemetry.currentPosition != null &&
                !_isInitLocationSet &&
                _mapController != null) {
              _mapController!.animateCamera(CameraUpdate.newLatLngZoom(
                  LatLng(telemetry.currentPosition!.latitude,
                      telemetry.currentPosition!.longitude),
                  16));
              _isInitLocationSet = true;
            }

            final sessionId = _activeSession?.id ?? telemetry.currentSessionId;
            final lapsStream = _firestoreService.getLaps(
              widget.raceId,
              _effectiveUserId,
              sessionId: sessionId,
              eventId: _currentEventId,
            );
            final passingsStream = _firestoreService.getPassingsStream(
              widget.raceId,
              sessionId: sessionId,
              eventId: _currentEventId,
              session: _activeSession,
            );

            final borderColor = _activeSession != null
                ? _getFlagColor(_activeSession!.currentFlag)
                : Colors.transparent;

            return Container(
              decoration: BoxDecoration(
                border: Border.all(color: borderColor, width: 4),
              ),
              child: Column(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    color: Colors.black,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildStatusIndicator(
                          telemetry.enableSendDataToCloud,
                          isSimulating: _telemetryService.isSimulating,
                          flag: _activeSession?.currentFlag,
                        ),
                        _buildModeToggle(),
                        _buildInfoMetric(
                          'Speed',
                          _telemetryService.isSimulating
                              ? '${(_telemetryService.simulationSpeed * 3.6).toStringAsFixed(1)} km/h'
                              : '${((telemetry.currentPosition?.speed ?? 0) * 3.6).toStringAsFixed(1)} km/h',
                          valueColor: Colors.white,
                        ),
                      ],
                    ),
                  ),
                  if (_activeSession == null &&
                      (sessionId == null || sessionId.isEmpty))
                    Container(
                      width: double.infinity,
                      color: Colors.black87,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      child: const Text(
                        'Sem sessao ativa detectada. Exibindo dados em fallback.',
                        style: TextStyle(color: Colors.amber, fontSize: 12),
                      ),
                    ),
                  Expanded(
                    child: StreamBuilder<QuerySnapshot>(
                      stream: lapsStream,
                      builder: (context, lapSnapshot) {
                        if (lapSnapshot.hasError) {
                          return Center(
                            child: Text(
                              'Error loading laps: ${lapSnapshot.error}',
                              style: const TextStyle(color: Colors.white70),
                              textAlign: TextAlign.center,
                            ),
                          );
                        }

                        final minLapMs =
                            (_activeSession?.minLapTimeSeconds ?? 0) * 1000;
                        final safeSessionStartMs = _activeSession != null
                            ? _resolveSafeSessionStartMs(_activeSession!)
                            : null;

                        return StreamBuilder<List<PassingModel>>(
                          stream: passingsStream,
                          builder: (context, passingSnapshot) {
                            if (passingSnapshot.hasError) {
                              return Center(
                                child: Text(
                                  'Error loading passings: ${passingSnapshot.error}',
                                  style: const TextStyle(color: Colors.white70),
                                  textAlign: TextAlign.center,
                                ),
                              );
                            }

                            final passings =
                                passingSnapshot.data ?? const <PassingModel>[];
                            final completedLapTimes = <int>[];
                            int? latestLapCloseTs;

                            for (final passing in passings) {
                              if (!_isCurrentPilotPassing(passing)) {
                                continue;
                              }
                              final flags = passing.flags
                                  .map((f) => f.toLowerCase())
                                  .toSet();
                              if (flags.contains('invalid') ||
                                  flags.contains('deleted')) {
                                continue;
                              }

                              final lapMs = passing.lapTime?.round();
                              if (lapMs == null || lapMs <= 0) {
                                continue;
                              }
                              if (minLapMs > 0 && lapMs < minLapMs) {
                                continue;
                              }

                              final ts =
                                  passing.timestamp.millisecondsSinceEpoch;
                              if (safeSessionStartMs != null &&
                                  ts < safeSessionStartMs - 1000) {
                                continue;
                              }

                              if (latestLapCloseTs == null ||
                                  ts > latestLapCloseTs) {
                                latestLapCloseTs = ts;
                              }
                              completedLapTimes.add(lapMs);
                            }

                            int? currentLapStartTs;
                            if (_activeSession != null) {
                              currentLapStartTs =
                                  latestLapCloseTs ?? safeSessionStartMs;
                            } else {
                              currentLapStartTs =
                                  latestLapCloseTs ?? _localLapStartMs;
                            }

                            if (currentLapStartTs != null &&
                                _localLapStartMs != currentLapStartTs) {
                              _localLapStartMs = currentLapStartTs;
                            }

                            int? bestLapMs;
                            int? previousLapMs;
                            if (completedLapTimes.isNotEmpty) {
                              previousLapMs = completedLapTimes.last;
                              bestLapMs = completedLapTimes
                                  .reduce((a, b) => a < b ? a : b);
                            }

                            int? currentLapMs;
                            if (currentLapStartTs != null) {
                              final nowMs = _uiNow.millisecondsSinceEpoch;
                              final diff = nowMs - currentLapStartTs;
                              currentLapMs = diff > 0 ? diff : 0;
                            }

                            final best = bestLapMs != null
                                ? _formatLapTime(bestLapMs)
                                : '--:--.---';
                            final previous = previousLapMs != null
                                ? _formatLapTime(previousLapMs)
                                : '--:--.---';
                            final current = currentLapMs != null
                                ? _formatLapTime(currentLapMs)
                                : '--:--.---';

                            if (_mode == LiveTimerMode.simple) {
                              return _buildSimpleMode(
                                best: best,
                                previous: previous,
                                current: current,
                              );
                            }

                            if (_mode == LiveTimerMode.classic) {
                              return _buildClassicMode(
                                currentLap: current,
                                telemetry: telemetry,
                              );
                            }

                            return _buildGaugeMode(
                              currentLap: current,
                              telemetry: telemetry,
                            );
                          },
                        );
                      },
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(12),
                    color: Colors.black,
                    child: Column(
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.smart_toy,
                                color: Colors.greenAccent, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _telemetryService.isSimulating
                                    ? 'Simulation mode active.'
                                    : (_autoSimulationMode
                                        ? 'Simulation mode enabled. Waiting for active session...'
                                        : (_simulationConfigLoaded
                                            ? 'Simulation mode disabled for this user.'
                                            : 'Loading simulation config...')),
                                style: const TextStyle(
                                  color: Colors.greenAccent,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (_autoSimulationMode) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Text('Sim speed',
                                  style: TextStyle(color: Colors.white70)),
                              Expanded(
                                child: Slider(
                                  value: _telemetryService.simulationSpeed,
                                  min: 1,
                                  max: 100,
                                  onChanged: (val) {
                                    _telemetryService.setSimulationSpeed(val);
                                  },
                                ),
                              ),
                              Text(
                                  '${_telemetryService.simulationSpeed.toStringAsFixed(1)} m/s',
                                  style:
                                      const TextStyle(color: Colors.white70)),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildDeleteButton(bool enabled, String sessionId) {
    return IconButton(
      icon: Icon(Icons.delete, color: enabled ? Colors.red : Colors.grey),
      onPressed: enabled ? () => _confirmDeleteLaps(sessionId) : null,
      tooltip: 'Clear Laps',
    );
  }

  Future<void> _confirmDeleteLaps(String sessionId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Laps?'),
        content: const Text(
            'Are you sure you want to clear the laps? The session will be saved in history.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Clear', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _firestoreService.archiveCurrentLaps(
          widget.raceId,
          _effectiveUserId,
          sessionId,
          eventId: _currentEventId,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Laps archived and cleared.')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error clearing laps: $e')),
          );
        }
      }
    }
  }

  Color _getGpsColor(double hz) {
    if (hz < 0.5) {
      return Colors.red;
    } else if (hz < 1.0) {
      return Colors.orange;
    } else if (hz < 1.8) {
      return Colors.green;
    } else {
      return Colors.greenAccent;
    }
  }

  Widget _buildInfoMetric(String label, String value, {Color? valueColor}) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
        const SizedBox(height: 4),
        Text(value,
            style: TextStyle(
                color: valueColor ?? Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildStatusIndicator(
    bool isSendingToCloud, {
    bool isSimulating = false,
    RaceFlag? flag,
  }) {
    final isLive = isSendingToCloud || isSimulating;
    String label;
    Color color;

    if (flag != null) {
      switch (flag) {
        case RaceFlag.green:
          label = 'GREEN';
          color = Colors.green;
          break;
        case RaceFlag.warmup:
          label = 'WARMUP';
          color = SpeedDataTheme.flagPurple;
          break;
        case RaceFlag.yellow:
          label = 'YELLOW';
          color = Colors.orange;
          break;
        case RaceFlag.red:
          label = 'RED';
          color = Colors.red;
          break;
        case RaceFlag.checkered:
          label = 'CHECKERED';
          color = Colors.white;
          break;
      }
    } else if (isLive) {
      label = 'LIVE';
      color = Colors.green;
    } else {
      label = 'READY';
      color = Colors.orange;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color),
      ),
      child: Row(
        children: [
          Icon(Icons.circle, size: 10, color: color),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
