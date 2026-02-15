
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:speed_data/features/models/race_session_model.dart';
import 'package:speed_data/features/services/firestore_service.dart';
import 'package:speed_data/features/widgets/track_shape_widget.dart';

class AdminMapView extends StatefulWidget {
  final String raceId;
  final String raceName;
  final SessionType sessionType;

  const AdminMapView({
    Key? key,
    required this.raceId,
    required this.raceName,
    this.sessionType = SessionType.race,
  }) : super(key: key);

  @override
  State<AdminMapView> createState() => _AdminMapViewState();
}

class _AdminMapViewState extends State<AdminMapView> {
  final FirestoreService _firestoreService = FirestoreService();
  List<LatLng> _checkpoints = [];
  List<LatLng> _routePath = [];
  bool _isLoading = true;

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
        final checkpointsData = data['checkpoints'] as List<dynamic>?;
        final routeData = data['route_path'] as List<dynamic>?;

        List<LatLng> loadedCheckpoints = [];
        List<LatLng> loadedRoute = [];

        if (checkpointsData != null) {
          for (var p in checkpointsData) {
            if (p == null) continue;
            final lat = (p['lat'] as num?)?.toDouble() ?? 0.0;
            final lng = (p['lng'] as num?)?.toDouble() ?? 0.0;
            if (lat != 0.0 || lng != 0.0) {
              loadedCheckpoints.add(LatLng(lat, lng));
            }
          }
        }

        if (routeData != null) {
          for (var p in routeData) {
            if (p == null) continue;
            final lat = (p['lat'] as num?)?.toDouble() ?? 0.0;
            final lng = (p['lng'] as num?)?.toDouble() ?? 0.0;
            if (lat != 0.0 || lng != 0.0) {
              loadedRoute.add(LatLng(lat, lng));
            }
          }
        }

        if (mounted) {
          setState(() {
            _checkpoints = loadedCheckpoints;
            _routePath = loadedRoute;
            _isLoading = false;
          });
        }
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint('Error loading race data for map: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }

    if (_checkpoints.isEmpty && _routePath.isEmpty) {
      return const Center(
          child: Text('No track data available',
              style: TextStyle(color: Colors.white)));
    }

    return Container(
      color: Colors.black, // Dark background
      width: double.infinity,
      height: double.infinity,
      padding: const EdgeInsets.all(16),
      child: CustomPaint(
        painter: TrackPainter(
          checkpoints: _checkpoints,
          routePath: _routePath,
        ),
      ),
    );
  }
}
