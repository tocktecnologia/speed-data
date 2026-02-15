import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:speed_data/features/services/telemetry_service.dart';
import 'package:speed_data/features/services/firestore_service.dart';
import 'package:speed_data/features/models/race_session_model.dart';
import 'package:speed_data/utils/map_utils.dart';

class ActiveRaceScreen extends StatefulWidget {
  final String raceId;
  final String userId;
  final String raceName;

  const ActiveRaceScreen({
    Key? key,
    required this.raceId,
    required this.userId,
    required this.raceName,
  }) : super(key: key);

  @override
  State<ActiveRaceScreen> createState() => _ActiveRaceScreenState();
}

class _ActiveRaceScreenState extends State<ActiveRaceScreen> {
  GoogleMapController? _mapController;
  final FirestoreService _firestoreService = FirestoreService();
  late TelemetryService _telemetryService;
  Set<Marker> _raceMarkers = {};
  bool _isInitLocationSet = false;

  LatLng? _startLocation;
  Set<Polyline> _polylines = {};
  Color _userColor = Colors.blue; // Default

  // Auto-sync & Flag state
  String? _currentEventId;
  RaceSession? _activeSession;
  StreamSubscription? _statusSubscription;
  Color _sessionBackgroundColor = Colors.black;

  @override
  void initState() {
    super.initState();
    _telemetryService = TelemetryService();
    // Start GPS immediately but disable cloud sync
    _telemetryService.enableSendDataToCloud = false;

    // Use post-frame callback to ensure context is ready if needed,
    // though startRecording handles mostly logic.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _telemetryService.startRecording(widget.raceId, widget.userId);
    });

    _loadRaceDetails();
  }

  @override
  void dispose() {
    // Ensure we stop recording and dispose the service
    _telemetryService.stopRecording();
    _telemetryService.dispose();
    _statusSubscription?.cancel(); // Cancel subscription on dispose
    super.dispose();
  }

  Future<void> _loadRaceDetails() async {
    final stream = _firestoreService.getRaceStream(widget.raceId);
    
    // Auto-discover event for this track
    print('DEBUG [ActiveRace]: Looking for active event on track: ${widget.raceId}');
    _firestoreService.getActiveEventForTrack(widget.raceId).then((event) {
      if (event == null) {
        print('DEBUG [ActiveRace]: No active event found for track ${widget.raceId}');
        return;
      }
      
      if (mounted) {
        print('DEBUG [ActiveRace]: Found event "${event.name}" (${event.id})');
        setState(() => _currentEventId = event.id);
        
        // Listen to active session
        _statusSubscription?.cancel();
        _statusSubscription = _firestoreService.getEventActiveSessionStream(event.id).listen((session) {
          if (mounted) {
            if (session != null) {
              print('DEBUG [ActiveRace]: Active session detected: ${session.name} | Status: ${session.status.name} | Flag: ${session.currentFlag.name}');
            } else {
              print('DEBUG [ActiveRace]: No active session in event');
            }
            
            setState(() {
              _activeSession = session;
              if (session != null) {
                // Sync telemetry with active session
                _telemetryService.setSessionId(session.id);
                _telemetryService.enableSendDataToCloud = true;
                
                // Update UI Color
                _sessionBackgroundColor = _getFlagColor(session.currentFlag);
                print('DEBUG [ActiveRace]: Background color updated to ${session.currentFlag.name}');
              } else {
                _telemetryService.enableSendDataToCloud = false;
                _sessionBackgroundColor = Colors.black;
              }
            });
          }
        });
      }
    }).catchError((e) {
      print('DEBUG [ActiveRace]: Error finding event: $e');
    });

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

        if (checkpoints.isNotEmpty) {
          // Pass checkpoints to telemetry service for cloud function processing
          _telemetryService.setCheckpoints(checkpoints
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList());

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

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _telemetryService,
      child: Scaffold(
        backgroundColor: _sessionBackgroundColor,
        appBar: AppBar(
          title: Text('Race: ${widget.raceName}'),
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

            return Column(
              children: [
                // Info Panel - Now uses session flag color
                Container(
                  padding: const EdgeInsets.all(16),
                  color: _sessionBackgroundColor,
                  width: double.infinity,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildInfoMetric('Speed',
                          '${((telemetry.currentPosition?.speed ?? 0) * 3.6).toStringAsFixed(1)} km/h'),
                      _buildInfoMetric(
                        'GPS Hz',
                        '${telemetry.currentFrequency.toStringAsFixed(1)} Hz',
                        valueColor: _getGpsColor(telemetry.currentFrequency),
                      ),
                      _buildStatusIndicator(telemetry.enableSendDataToCloud),
                      _buildDeleteButton(!telemetry.enableSendDataToCloud,
                          telemetry.currentSessionId!),
                    ],
                  ),
                ),

                // Map
                Expanded(
                  child: Stack(
                    children: [
                      GoogleMap(
                        initialCameraPosition: const CameraPosition(
                          target: LatLng(
                              -15.793889, -47.882778), // Default before GPS
                          zoom: 16,
                        ),
                        onMapCreated: _onMapCreated,
                        myLocationEnabled: true,
                        myLocationButtonEnabled: true,
                        markers: {
                          ..._raceMarkers,
                          if (telemetry.currentPosition != null)
                            Marker(
                              markerId: const MarkerId('my_position'),
                              position: LatLng(
                                telemetry.currentPosition!.latitude,
                                telemetry.currentPosition!.longitude,
                              ),
                              icon: BitmapDescriptor.defaultMarkerWithHue(
                                HSVColor.fromColor(_userColor).hue,
                              ),
                              zIndex: 10,
                            ),
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
                  child: Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: telemetry.enableSendDataToCloud
                              ? null
                              : () {
                                  telemetry.enableSendDataToCloud = true;
                                  // Force rebuild to update button state since setter doesn't notify
                                  setState(() {});
                                },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            disabledBackgroundColor: Colors.grey[800],
                            disabledForegroundColor: Colors.grey,
                          ),
                          child: const Text('START'),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: !telemetry.enableSendDataToCloud
                              ? null
                              : () async {
                                  await telemetry.stopRecording();
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                          content: Text(
                                              'Race Finalized & Uploading...')),
                                    );
                                    Navigator.of(context).pop(); // Go back
                                  }
                                },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            disabledBackgroundColor: Colors.grey[800],
                            disabledForegroundColor: Colors.grey,
                          ),
                          child: const Text('FINISH RACE'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
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

  Widget _buildStatusIndicator(bool isSendingToCloud) {
    // If we're not sending to cloud, but GPS is running (which it generally is), show READY/GPS ON
    // If sending to cloud, show LIVE
    final isLive = isSendingToCloud;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isLive
            ? Colors.green.withOpacity(0.2)
            : Colors.orange.withOpacity(0.2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isLive ? Colors.green : Colors.orange),
      ),
      child: Row(
        children: [
          Icon(Icons.circle,
              size: 10, color: isLive ? Colors.green : Colors.orange),
          const SizedBox(width: 8),
          Text(
            isLive ? 'LIVE' : 'JÁ NO GRID',
            style: TextStyle(
              color: isLive ? Colors.green : Colors.orange,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
