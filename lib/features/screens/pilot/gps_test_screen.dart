import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart';
import 'package:speed_data/features/services/firestore_service.dart';
import 'package:speed_data/features/models/race_session_model.dart';
import 'package:speed_data/utils/map_utils.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

class GpsTestScreen extends StatefulWidget {
  final String raceId;
  final String userId;
  final String raceName;

  const GpsTestScreen({
    Key? key,
    required this.raceId,
    required this.userId,
    required this.raceName,
  }) : super(key: key);

  @override
  State<GpsTestScreen> createState() => _GpsTestScreenState();
}

class _GpsTestScreenState extends State<GpsTestScreen> {
  GoogleMapController? _mapController;
  final FirestoreService _firestoreService = FirestoreService();

  Set<Marker> _raceMarkers = {};
  Set<Polyline> _polylines = {};
  LatLng? _startLocation;
  List<Map<String, dynamic>>? _checkpoints;

  // Simulation State
  bool _isSimulating = false;
  double _simulationSpeed = 40.0; // m/s
  Timer? _simulationTimer;
  List<LatLng> _routePath = [];
  double _currentRouteDistance = 0.0;
  Color _userColor = Colors.cyan; // Default color

  // "Telemetry" State for UI
  double _currentSpeed = 0.0; // m/s
  double _currentHz = 0.0;
  LatLng? _currentPosition;

  // Simulation config
  final int _updatesPerSecond = 1;

  // Telemetry Syncing
  List<Map<String, dynamic>> _buffer = [];
  Timer? _syncTimer;
  String? _currentSessionId;
  bool _enableSendDataToCloud = true;
  static const int _syncIntervalSeconds = 5;

  // Auto-sync & Flag state
  String? _currentEventId;
  StreamSubscription? _statusSubscription;
  Color _sessionBackgroundColor = Colors.black;
  String _driverName = 'Unknown Driver'; // Driver name for passing records

  void initState() {
    super.initState();
    _loadRaceDetails();
  }

  @override
  void dispose() {
    _statusSubscription?.cancel();
    _simulationTimer?.cancel();
    _syncTimer?.cancel();
    WakelockPlus.disable();
    super.dispose();
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

  Future<void> _loadRaceDetails() async {
    // Auto-discover event for this track
    _firestoreService.getActiveEventForTrack(widget.raceId).then((event) async {
      if (event != null && mounted) {
        setState(() => _currentEventId = event.id);
        
        // Fetch driver name from competitor data (NOW that we have eventId)
        print('DEBUG [GpsTest]: Fetching driver name for user ${widget.userId} in event ${event.id}');
        try {
          final competitor = await _firestoreService.getCompetitorByUid(event.id, widget.userId);
          print('DEBUG [GpsTest]: Competitor data = $competitor');
          if (competitor != null) {
            final fullName = '${competitor.firstName} ${competitor.lastName}'.trim();
            if (mounted) {
              setState(() {
                _driverName = fullName.isNotEmpty ? fullName : 'Unknown Driver';
              });
            }
            print('DEBUG [GpsTest]: Driver name loaded: $_driverName');
          } else {
            print('DEBUG [GpsTest]: Competitor not found for this user in event ${event.id}');
          }
        } catch (e) {
          print('DEBUG [GpsTest]: Error fetching competitor name: $e');
        }
        
        // Listen to active session
        _statusSubscription?.cancel();
        _statusSubscription = _firestoreService.getEventActiveSessionStream(event.id).listen((session) {
          if (mounted) {
            setState(() {
               if (session != null) {
                  // Sync telemetry with active session
                  _currentSessionId = session.id;
                  
                  // Update UI Color
                  _sessionBackgroundColor = _getFlagColor(session.currentFlag);
               } else {
                  _sessionBackgroundColor = Colors.black;
               }
            });
          }
        });
      }
    });

    final stream = _firestoreService.getRaceStream(widget.raceId);
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

      if (checkpoints != null && checkpoints.isNotEmpty) {
        // Cast strictly to ensure type safety
        _checkpoints = checkpoints
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        final markers = <Marker>{};
        final straightRoutePoints = <LatLng>[];

        // Process First Point
        final firstPoint = checkpoints[0];
        final fLat = (firstPoint['lat'] as num).toDouble();
        final fLng = (firstPoint['lng'] as num).toDouble();
        _startLocation = LatLng(fLat, fLng);
        _currentPosition = _startLocation;

        if (_mapController != null && mounted) {
          _mapController!
              .moveCamera(CameraUpdate.newLatLngZoom(_startLocation!, 16));
        }

        // Build Markers
        for (int i = 0; i < checkpoints.length; i++) {
          final point = checkpoints[i];
          final lat = (point['lat'] as num).toDouble();
          final lng = (point['lng'] as num).toDouble();

          // Skip loop closure marker if needed
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
          straightRoutePoints.add(position);
          final String label = String.fromCharCode(65 + i);

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

        // Build Route Path
        List<LatLng> finalRoutePoints = straightRoutePoints;
        final savedRoutePath = data['route_path'] as List<dynamic>?;

        if (savedRoutePath != null && savedRoutePath.isNotEmpty) {
          finalRoutePoints = savedRoutePath.map((p) {
            return LatLng(
                (p['lat'] as num).toDouble(), (p['lng'] as num).toDouble());
          }).toList();
        } else {
          // Close loop if straight lines
          if (straightRoutePoints.length > 2) {
            finalRoutePoints.add(straightRoutePoints.first);
          }
        }

        _routePath = finalRoutePoints;

        // Build Polylines
        final polylines = <Polyline>{};
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
    }
  }

  void _startSimulation() async {
    if (_routePath.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No route path available')));
      return;
    }

    await WakelockPlus.enable();

    final totalLength = _calculatePathLength(_routePath);
    // Start 50 meters before the start point (Checkpoint A)
    double initialDistance = 0.0;
    if (totalLength > 50) {
      initialDistance = totalLength - 50;
    }

    setState(() {
      _isSimulating = true;
      _currentRouteDistance = initialDistance;
      _currentHz = _updatesPerSecond.toDouble();
      _currentSpeed = _simulationSpeed * 3.6;
    });

    final int intervalMs = (1000 / _updatesPerSecond).round();

    print('DEBUG [GpsTest]: Starting simulation with session ID: $_currentSessionId');
    _buffer.clear();
    // Session ID is now set automatically from Firestore event listener
    // No need to generate a new one here

    _syncTimer =
        Timer.periodic(const Duration(seconds: _syncIntervalSeconds), (_) {
      _syncData();
    });

    _simulationTimer =
        Timer.periodic(Duration(milliseconds: intervalMs), (timer) {
      _simulateTick(intervalMs / 1000.0);
    });
  }

  void _stopSimulation() async {
    _simulationTimer?.cancel();
    _simulationTimer = null;
    _syncTimer?.cancel();
    _syncTimer = null;
    _syncData(); // Final flush
    await WakelockPlus.disable();
    setState(() {
      _isSimulating = false;
      _currentSpeed = 0.0;
      _currentHz = 0.0;
    });
  }

  void _simulateTick(double dt) {
    // distance = speed * time
    final stepDistance = _simulationSpeed * dt; // meters

    _currentRouteDistance += stepDistance;

    // Get total length approx
    // Ideally we should pre-calculate cumulative distances for performance,
    // but for a test screen, calculating on fly is okay or we can improve.

    final totalLength = _calculatePathLength(_routePath);
    if (_currentRouteDistance >= totalLength) {
      _currentRouteDistance = 0; // Loop
    }

    final newPos = _getPointAtDistance(_currentRouteDistance, _routePath);

    setState(() {
      _currentPosition = newPos;
    });

    // Add to buffer
    final point = {
      'raceId': widget.raceId,
      'uid': widget.userId,
      'session': _currentSessionId,
      'lat': newPos.latitude,
      'lng': newPos.longitude,
      'speed': _simulationSpeed, // m/s
      'heading': 0.0, // Could calculate bearing if needed
      'altitude': 0.0,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
    _buffer.add(point);

    // Move camera (optional)
    // _mapController?.animateCamera(CameraUpdate.newLatLng(newPos));
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
        // Point is in this segment
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _sessionBackgroundColor,
      appBar: AppBar(
        title: Text('GPS Test: ${widget.raceName}'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // Info Panel (Replication of ActiveRaceScreen) - Now uses session flag color
          Container(
            padding: const EdgeInsets.all(16),
            color: _sessionBackgroundColor,
            width: double.infinity,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildInfoMetric(
                    'Speed', '${(_currentSpeed).toStringAsFixed(1)} km/h '),
                _buildInfoMetric(
                    'GPS Hz', '${_currentHz.toStringAsFixed(1)} Hz',
                    valueColor: _getGpsColor(_currentHz)),
                _buildStatusIndicator(_isSimulating),
                _buildDeleteButton(),
              ],
            ),
          ),

          // Map
          Expanded(
            child: Stack(
              children: [
                GoogleMap(
                  initialCameraPosition: const CameraPosition(
                    target: LatLng(-15.793889, -47.882778),
                    zoom: 16,
                  ),
                  onMapCreated: _onMapCreated,
                  myLocationEnabled:
                      true, // We might not see "blue dot" if we don't mock location provider, but we can use a marker for simulated pos
                  myLocationButtonEnabled: true,
                  markers: {
                    ..._raceMarkers,
                    if (_currentPosition != null)
                      Marker(
                        markerId: const MarkerId('simulated_pos'),
                        position: _currentPosition!,
                        icon: BitmapDescriptor.defaultMarkerWithHue(
                          HSVColor.fromColor(_userColor).hue,
                        ),
                        zIndex: 10,
                      )
                  },
                  polylines: _polylines,
                ),
              ],
            ),
          ),

          // Controls - Also uses session flag color
          Container(
            padding: const EdgeInsets.all(20),
            color: _sessionBackgroundColor.withOpacity(0.9),
            child: Column(
              children: [
                // Speed Parameter
                Row(
                  children: [
                    const Text('Sim Speed:',
                        style: TextStyle(color: Colors.white)),
                    Expanded(
                        child: Slider(
                      value: _simulationSpeed,
                      min: 1,
                      max: 100, // up to 360km/h
                      onChanged: (val) {
                        setState(() {
                          _simulationSpeed = val;
                          if (_isSimulating) {
                            _currentSpeed = val * 3.6;
                          }
                        });
                      },
                    )),
                    Text('${_simulationSpeed.toStringAsFixed(1)} m/s',
                        style: const TextStyle(color: Colors.white)),
                  ],
                ),

                const SizedBox(height: 10),

                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _isSimulating ? null : _startSimulation,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          disabledBackgroundColor: Colors.grey[800],
                        ),
                        child: const Text('START SIMULATION'),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: !_isSimulating ? null : _stopSimulation,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          disabledBackgroundColor: Colors.grey[800],
                        ),
                        child: const Text('STOP'),
                      ),
                    )
                  ],
                )
              ],
            ),
          ),
        ],
      ),
    );
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

  Widget _buildStatusIndicator(bool isSimulating) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isSimulating
            ? Colors.green.withOpacity(0.2)
            : Colors.orange.withOpacity(0.2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isSimulating ? Colors.green : Colors.orange),
      ),
      child: Row(
        children: [
          Icon(Icons.circle,
              size: 10, color: isSimulating ? Colors.green : Colors.orange),
          const SizedBox(width: 8),
          Text(
            isSimulating ? 'SIMULATING' : 'READY',
            style: TextStyle(
              color: isSimulating ? Colors.green : Colors.orange,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeleteButton() {
    final bool enabled = !_isSimulating;
    return IconButton(
      icon: Icon(Icons.delete, color: enabled ? Colors.red : Colors.grey),
      onPressed: enabled ? _confirmDeleteLaps : null,
      tooltip: 'Clear Laps',
    );
  }

  Future<void> _confirmDeleteLaps() async {
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
            widget.raceId, widget.userId, _currentSessionId!);
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

  Future<void> _syncData() async {
    if (_buffer.isEmpty) return;

    // Snapshot buffer and clear main buffer to allow new writes
    final batch = List<Map<String, dynamic>>.from(_buffer);
    _buffer.clear();

    try {
      // 1. Send Batch to Cloud Function
      if (_enableSendDataToCloud) {
        await _firestoreService.sendTelemetryBatch(
          widget.raceId, 
          widget.userId,
          batch, 
          _checkpoints, 
          _currentSessionId,
        );
      }

      if (kDebugMode) {
        print('Synced telemetry batch: ${batch.length} points');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error syncing telemetry batch: $e');
      }
      // On failure, restore data to the buffer
      _buffer.insertAll(0, batch);
    }
  }
}
