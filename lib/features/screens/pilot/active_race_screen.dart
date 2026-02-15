import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:speed_data/features/services/telemetry_service.dart';
import 'package:speed_data/features/services/firestore_service.dart';
import 'package:speed_data/features/models/race_session_model.dart';
import 'package:speed_data/utils/map_utils.dart';
import 'package:speed_data/features/widgets/track_shape_widget.dart';

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


  @override
  void initState() {
    super.initState();
    _telemetryService = TelemetryService.instance;

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

    Future<void> attachEventListeners(String eventId) async {
      if (!mounted) return;
      setState(() => _currentEventId = eventId);

      _statusSubscription?.cancel();
      _statusSubscription = _firestoreService
          .getEventActiveSessionStream(eventId)
          .listen((session) {
        if (!mounted) return;
        setState(() {
          _activeSession = session;
          if (session != null) {
            _telemetryService.setSessionId(session.id);
            if (!_telemetryService.isSimulating) {
              _telemetryService.enableSendDataToCloud = true;
              if (!_telemetryService.isRecording) {
                _telemetryService.startRecording(widget.raceId, widget.userId);
              }
            }
            _sessionBackgroundColor = _getFlagColor(session.currentFlag);
          } else {
            _telemetryService.enableSendDataToCloud = false;
            _sessionBackgroundColor = Colors.black;
          }
        });
      });
    }

    if (widget.eventId != null && widget.eventId!.isNotEmpty) {
      await attachEventListeners(widget.eventId!);
    } else {
      _firestoreService.getActiveEventForTrack(widget.raceId).then((event) {
        if (event == null) return;
        attachEventListeners(event.id);
      }).catchError((_) {});
    }

    final snapshot = await stream.first;

    // Fetch user color
    try {
      final userProfile = await _firestoreService.getUserProfile(widget.userId);
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
      }
    }
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
      case RaceFlag.yellow:
        return Colors.orange.withOpacity(0.8);
      case RaceFlag.red:
        return Colors.red.withOpacity(0.8);
      case RaceFlag.checkered:
        return Colors.white.withOpacity(0.9);
      default:
        return Colors.black;
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

  Future<void> _startSimulation() async {
    if (_activeSession == null || _activeSession!.id.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No active session to simulate')));
      return;
    }
    if (_routePath.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No route path available')));
      return;
    }
    await _telemetryService.startSimulation(
      routePath: _routePath,
      checkpoints: _checkpoints,
      raceId: widget.raceId,
      userId: widget.userId,
      sessionId: _activeSession!.id,
    );
  }

  Future<void> _stopSimulation() async {
    await _telemetryService.stopSimulation();
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
              uid: widget.userId,
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

            final sessionId = _activeSession?.id;
            final lapsStream = sessionId == null
                ? null
                : _firestoreService.getLaps(
                    widget.raceId,
                    widget.userId,
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
                  Expanded(
                    child: sessionId == null
                        ? const Center(
                            child: Text(
                              'Aguardando sessao ativa...',
                              style: TextStyle(color: Colors.white70),
                            ),
                          )
                        : StreamBuilder(
                            stream: lapsStream,
                            builder: (context, snapshot) {
                              if (!snapshot.hasData) {
                                return const Center(
                                    child: CircularProgressIndicator());
                              }

                              final docs = snapshot.data!.docs;
                              int? currentLapStartTs;
                              final completedLapTimes = <int>[];
                              final sessionStartMs = _activeSession
                                  ?.actualStartTime?.millisecondsSinceEpoch;
                              final sessionEndMs = _activeSession
                                  ?.actualEndTime?.millisecondsSinceEpoch;
                              final minLapMs =
                                  (_activeSession?.minLapTimeSeconds ?? 0) *
                                      1000;

                              bool inSessionWindow(int? lapStartMs) {
                                if (lapStartMs == null)
                                  return sessionStartMs == null;
                                if (sessionStartMs != null &&
                                    lapStartMs < sessionStartMs) {
                                  return false;
                                }
                                if (sessionEndMs != null &&
                                    lapStartMs > sessionEndMs) {
                                  return false;
                                }
                                return true;
                              }

                              for (var i = 0; i < docs.length; i++) {
                                final data =
                                    docs[i].data() as Map<String, dynamic>;
                                final lapStartTs =
                                    _extractLapStartTimestamp(data);
                                if (!inSessionWindow(lapStartTs)) {
                                  continue;
                                }
                                if (currentLapStartTs == null) {
                                  currentLapStartTs = lapStartTs;
                                }
                                final t = data['totalLapTime'];
                                int? lapMs;
                                if (t is int) {
                                  lapMs = t;
                                } else if (t is num) {
                                  lapMs = t.toInt();
                                }
                                if (lapMs != null &&
                                    (minLapMs == 0 || lapMs >= minLapMs)) {
                                  completedLapTimes.add(lapMs);
                                }
                              }

                              int? bestLapMs;
                              int? previousLapMs;
                              if (completedLapTimes.isNotEmpty) {
                                previousLapMs = completedLapTimes.first;
                                bestLapMs = completedLapTimes
                                    .reduce((a, b) => a < b ? a : b);
                              }

                              int? currentLapMs;
                              if (currentLapStartTs != null) {
                                final nowMs = _uiNow.millisecondsSinceEpoch;
                                final diff = nowMs - currentLapStartTs!;
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
                          ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(12),
                    color: Colors.black,
                    child: Column(
                      children: [
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
                                style: const TextStyle(color: Colors.white70)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton(
                                onPressed: _telemetryService.isSimulating
                                    ? null
                                    : _startSimulation,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12),
                                  disabledBackgroundColor: Colors.grey[800],
                                  disabledForegroundColor: Colors.grey,
                                ),
                                child: const Text('START SIMULATION'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: !_telemetryService.isSimulating
                                    ? null
                                    : _stopSimulation,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12),
                                  disabledBackgroundColor: Colors.grey[800],
                                  disabledForegroundColor: Colors.grey,
                                ),
                                child: const Text('STOP'),
                              ),
                            ),
                          ],
                        ),
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
            widget.raceId, widget.userId, sessionId);
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
