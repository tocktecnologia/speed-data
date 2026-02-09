import 'dart:math';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:speed_data/features/screens/admin/widgets/leaderboard_panel.dart';
import 'package:speed_data/features/services/firestore_service.dart';
import 'package:speed_data/utils/map_utils.dart';

class AdminMapView extends StatefulWidget {
  final String raceId;
  final String raceName;

  const AdminMapView({Key? key, required this.raceId, required this.raceName})
      : super(key: key);

  @override
  State<AdminMapView> createState() => _AdminMapViewState();
}

class _AdminMapViewState extends State<AdminMapView> {
  final FirestoreService _firestoreService = FirestoreService();
  GoogleMapController? _mapController;
  LatLng? _initialCameraTarget;
  List<dynamic> _checkpoints = [];
  Set<Marker> _staticMarkers = {};
  Set<Polyline> _polylines = {};

  @override
  void initState() {
    super.initState();
    _loadRaceData();
  }

  Future<void> _loadRaceData() async {
    try {
      final doc = await _firestoreService.getRaceStream(widget.raceId).first;
      if (doc.exists && doc.data() != null) {
        final data = doc.data() as Map<String, dynamic>;
        final checkpoints = data['checkpoints'] as List<dynamic>?;
        final savedRoutePath = data['route_path'] as List<dynamic>?;

        Set<Marker> markers = {};
        Set<Polyline> polylines = {};

        // Parse Checkpoints
        if (checkpoints != null && checkpoints.isNotEmpty) {
          List<LatLng> straightRoutePoints = [];

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
        }

        // Parse Route
        if (savedRoutePath != null && savedRoutePath.isNotEmpty) {
          final routePoints = savedRoutePath.map((p) {
            return LatLng(
                (p['lat'] as num).toDouble(), (p['lng'] as num).toDouble());
          }).toList();

          polylines.add(
            Polyline(
              polylineId: const PolylineId('race_route'),
              points: routePoints,
              color: Colors.blue,
              width: 5,
            ),
          );
        }

        if (mounted) {
          setState(() {
            _checkpoints = checkpoints ?? [];
            _staticMarkers = markers;
            _polylines = polylines;
          });

          if (checkpoints != null && checkpoints.isNotEmpty) {
            final firstPoint = checkpoints.first as Map<String, dynamic>;
            _initialCameraTarget = LatLng((firstPoint['lat'] as num).toDouble(),
                (firstPoint['lng'] as num).toDouble());
          } else {
            _useDefaultLocation();
          }
        }
      } else {
        _useDefaultLocation();
      }
    } catch (e) {
      debugPrint('Error loading race data: $e');
      _useDefaultLocation();
    }
  }

  void _useDefaultLocation() {
    if (mounted) {
      setState(() {
        _initialCameraTarget =
            const LatLng(-15.793889, -47.882778); // Default Brazil
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_initialCameraTarget == null) {
      return Scaffold(
        appBar: AppBar(
          title: Text('Monitoring: ${widget.raceName}'),
          backgroundColor: Colors.black,
        ),
        body: const Center(
          child: CircularProgressIndicator(color: Colors.black),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Monitoring: ${widget.raceName}'),
        backgroundColor: Colors.black,
      ),
      body: Stack(
        children: [
          StreamBuilder<QuerySnapshot>(
            stream: _firestoreService.getRaceLocations(widget.raceId),
            builder: (context, snapshot) {
              Set<Marker> markers = {};
              markers.addAll(_staticMarkers);

              if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
                markers.addAll(_createMarkers(snapshot.data!.docs));
              }

              return GoogleMap(
                initialCameraPosition: CameraPosition(
                  target: _initialCameraTarget!,
                  zoom: 16, // Use a closer zoom for races
                ),
                markers: markers,
                polylines: _polylines,
                onMapCreated: (controller) => _mapController = controller,
                myLocationEnabled: true,
                myLocationButtonEnabled: true,
              );
            },
          ),
          LeaderboardPanel(
            raceId: widget.raceId,
            checkpoints: _checkpoints,
          ),
        ],
      ),
    );
  }

  Set<Marker> _createMarkers(List<QueryDocumentSnapshot> docs) {
    final newMarkers = <Marker>{};
    for (var doc in docs) {
      final data = doc.data() as Map<String, dynamic>;

      final displayName = data['display_name'] as String? ?? 'Pilot ${doc.id}';
      final displayColor = data['color'] as String? ?? '0x0000FF';

      // Check if 'current' field exists and is a Map
      if (data.containsKey('current') &&
          data['current'] is Map<String, dynamic>) {
        final current = data['current'] as Map<String, dynamic>;
        final lat = (current['lat'] as num?)?.toDouble();
        final lng = (current['lng'] as num?)?.toDouble();
        final speed = (current['speed'] as num?)?.toDouble() ?? 0.0;
        final heading = (current['heading'] as num?)?.toDouble() ?? 0.0;

        if (lat != null && lng != null) {
          final pos = LatLng(lat, lng);

          newMarkers.add(
            Marker(
              markerId: MarkerId(doc.id),
              position: pos,
              rotation: heading,
              infoWindow: InfoWindow(
                title: displayName == ""
                    ? "Pilot id: ${doc.id.substring(0, 6)}"
                    : displayName,
                snippet: 'Speed: ${(speed * 3.6).toStringAsFixed(1)} km/h',
              ),
              icon: BitmapDescriptor.defaultMarkerWithHue(
                HSVColor.fromColor(Color(int.parse(displayColor))).hue,
                // BitmapDescriptor.hueAzure,
              ),
            ),
          );
        }
      }
    }
    return newMarkers;
  }
}
