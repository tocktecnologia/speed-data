import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:speed_data/features/services/firestore_service.dart';

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

        if (checkpoints != null && checkpoints.isNotEmpty) {
          final firstPoint = checkpoints.first as Map<String, dynamic>;
          final lat = (firstPoint['lat'] as num).toDouble();
          final lng = (firstPoint['lng'] as num).toDouble();
          if (mounted) {
            setState(() {
              _initialCameraTarget = LatLng(lat, lng);
            });
          }
        } else {
          _useDefaultLocation();
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
      body: StreamBuilder<QuerySnapshot>(
        stream: _firestoreService.getRaceLocations(widget.raceId),
        builder: (context, snapshot) {
          Set<Marker> markers = {};

          if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
            markers = _createMarkers(snapshot.data!.docs);
          }

          return GoogleMap(
            initialCameraPosition: CameraPosition(
              target: _initialCameraTarget!,
              zoom: 16, // Use a closer zoom for races
            ),
            markers: markers,
            onMapCreated: (controller) => _mapController = controller,
            myLocationEnabled: true,
            myLocationButtonEnabled: true,
          );
        },
      ),
    );
  }

  Set<Marker> _createMarkers(List<QueryDocumentSnapshot> docs) {
    final newMarkers = <Marker>{};
    for (var doc in docs) {
      final data = doc.data() as Map<String, dynamic>;

      // Check if 'current' field exists and is a Map
      if (data.containsKey('current') &&
          data['current'] is Map<String, dynamic>) {
        final current = data['current'] as Map<String, dynamic>;
        final lat = (current['lat'] as num?)?.toDouble();
        final lng = (current['lng'] as num?)?.toDouble();
        final speed = (current['speed'] as num?)?.toDouble() ?? 0.0;
        final heading = (current['heading'] as num?)?.toDouble() ?? 0.0;
        final displayName =
            data['display_name'] as String? ?? 'Pilot ${doc.id}';

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
                  BitmapDescriptor.hueAzure),
            ),
          );
        }
      }
    }
    return newMarkers;
  }
}
