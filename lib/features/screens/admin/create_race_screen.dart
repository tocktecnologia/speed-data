import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:speed_data/features/services/firestore_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:speed_data/utils/map_utils.dart';
import 'package:speed_data/features/services/route_service.dart';

class CreateRaceScreen extends StatefulWidget {
  final String? raceId;
  final Map<String, dynamic>? initialData;
  final bool readOnly;

  const CreateRaceScreen({Key? key, this.raceId, this.initialData, this.readOnly = false})
      : super(key: key);

  @override
  State<CreateRaceScreen> createState() => _CreateRaceScreenState();
}

class _CreateRaceScreenState extends State<CreateRaceScreen> {
  final _raceNameController = TextEditingController();
  final FirestoreService _firestoreService = FirestoreService();
  final RouteService _routeService = RouteService();

  GoogleMapController? _mapController;
  final List<LatLng> _checkpoints = [];
  List<LatLng> _routePath = []; // Detailed path from API
  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};

  final LatLng _initialPos =
      const LatLng(-3.8903, -38.4556); // Eusébio, Ceará

  @override
  void initState() {
    super.initState();
    if (widget.initialData != null) {
      _loadInitialData();
    }
  }

  void _loadInitialData() {
    final data = widget.initialData!;
    _raceNameController.text = data['name'] ?? '';

    if (data['checkpoints'] != null) {
      final List<dynamic> points = data['checkpoints'];
      _checkpoints.addAll(points.map((p) {
        final lat = (p['lat'] as num).toDouble();
        final lng = (p['lng'] as num).toDouble();
        return LatLng(lat, lng);
      }));
    }

    if (data['route_path'] != null) {
      final List<dynamic> route = data['route_path'];
      _routePath = route.map((p) {
        final lat = (p['lat'] as num).toDouble();
        final lng = (p['lng'] as num).toDouble();
        return LatLng(lat, lng);
      }).toList();
    }

    // We need to wait for the build to complete before updating markers
    // because createCustomMarkerBitmap might depend on context/assets
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Create markers but DO NOT trigger route recalculation (updatePolyline: false)
      _updateMarkers(updatePolyline: false);

      // Manually set the polyline from the loaded route path
      setState(() {
        _polylines = {
          Polyline(
            polylineId: const PolylineId('race_route'),
            points: _routePath,
            color: Colors.blue,
            width: 5,
          ),
        };
      });
    });
  }

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
    if (_checkpoints.isNotEmpty) {
      // If we have checkpoints (editing/viewing), center on the first one immediately
      _mapController?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: _checkpoints.first, zoom: 16),
        ),
      );
    } else {
      // Otherwise try to get current location
      Future.delayed(const Duration(milliseconds: 500), _getCurrentLocation);
    }
  }

  Future<void> _getCurrentLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      debugPrint('Location services are disabled.');
      return;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        debugPrint('Location permissions are denied');
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      debugPrint('Location permissions are permanently denied');
      return;
    }

    try {
      Position? lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null && mounted) {
        _mapController?.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: LatLng(lastKnown.latitude, lastKnown.longitude),
              zoom: 16,
            ),
          ),
        );
      }

      // If editing, center on the first checkpoint
      if (widget.initialData != null && _checkpoints.isNotEmpty) {
        if (!mounted) return;
        _mapController?.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: _checkpoints.first,
              zoom: 16,
            ),
          ),
        );
        return;
      }

      Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);

      if (!mounted) return;

      _mapController?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: LatLng(position.latitude, position.longitude),
            zoom: 16,
          ),
        ),
      );
    } catch (e) {
      debugPrint('Error getting location: $e');
    }
  }

  void _onMapTap(LatLng pos) {
    _checkpoints.add(pos);
    _updateMarkers();
  }

  void _undoCheckpoint() {
    if (_checkpoints.isNotEmpty) {
      _checkpoints.removeLast();
      _updateMarkers();
    }
  }

  void _clearCheckpoints() {
    _checkpoints.clear();
    _updateMarkers();
  }

  Future<void> _updateMarkers({bool updatePolyline = true}) async {
    final markers = <Marker>{};

    for (int i = 0; i < _checkpoints.length; i++) {
      LatLng point = _checkpoints[i];
      String label = String.fromCharCode(65 + i); // A, B, C...

      final icon = await createCustomMarkerBitmap(label,
          color: i == 0 ? Colors.green : Colors.red);

      markers.add(
        Marker(
            markerId: MarkerId('checkpoint_$i'),
            position: point,
            infoWindow: InfoWindow(title: 'Checkpoint $label'),
            icon: icon,
            onTap: () {
              // If user taps the first (Green) marker and we have a path started
              if (i == 0 && _checkpoints.length > 1) {
                // Avoid adding it if it is already the last one (double tap prevention)
                if (_checkpoints.last != _checkpoints.first) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Closing race loop...')),
                  );
                  setState(() {
                    _checkpoints.add(_checkpoints.first);
                    _updateMarkers(); // Triggers generic marker/polyline update
                  });
                }
              }
            }),
      );
    }

    if (mounted) {
      setState(() {
        _markers = markers;
        if (updatePolyline) {
          _updatePolylines();
        }
      });
    }
  }

  Future<void> _updatePolylines() async {
    if (_checkpoints.length > 1) {
      final densePath = await _routeService.getRouteBetweenPoints(_checkpoints);

      if (mounted) {
        setState(() {
          _routePath = densePath;
          _polylines = {
            Polyline(
              polylineId: const PolylineId('race_route'),
              points: _routePath,
              color: Colors.blue,
              width: 5,
            ),
          };
        });
      }
    } else {
      if (mounted) {
        setState(() {
          _routePath = [];
          _polylines = {};
        });
      }
    }
  }

  Future<void> _saveRace() async {
    final name = _raceNameController.text.trim();
    final user = FirebaseAuth.instance.currentUser;

    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a race name')),
      );
      return;
    }

    if (_checkpoints.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Please define at least 2 checkpoints (A -> B)')),
      );
      return;
    }

    if (user == null) return;

    final pointsList = _checkpoints
        .map((p) => {
              'lat': p.latitude,
              'lng': p.longitude,
            })
        .toList();

    final routeList = _routePath
        .map((p) => {
              'lat': p.latitude,
              'lng': p.longitude,
            })
        .toList();

    if (widget.raceId != null) {
      await _firestoreService.updateRace(
        widget.raceId!,
        name: name,
        checkpoints: pointsList,
        routePath: routeList,
      );
    } else {
      await _firestoreService.createRace(
        name,
        user.uid,
        checkpoints: pointsList,
        routePath: routeList,
      );
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(widget.raceId != null
                ? 'Race updated successfully!'
                : 'Race created successfully!')),
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.readOnly
            ? 'View Race Plan'
            : (widget.raceId != null ? 'Edit Race Plan' : 'Create Race Plan')),
        backgroundColor: Colors.black,
        actions: widget.readOnly
            ? []
            : [
                IconButton(
                  icon: const Icon(Icons.undo),
                  onPressed: _undoCheckpoint,
                  tooltip: 'Undo Last Checkpoint',
                ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _clearCheckpoints,
                  tooltip: 'Clear All',
                )
              ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _raceNameController,
              readOnly: widget.readOnly,
              decoration: const InputDecoration(
                labelText: 'Race Name',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.flag),
              ),
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                GoogleMap(
                  onMapCreated: _onMapCreated,
                  initialCameraPosition: CameraPosition(
                    target: _initialPos,
                    zoom: 12,
                  ),
                  onTap: widget.readOnly ? null : _onMapTap,
                  markers: _markers,
                  polylines: _polylines,
                  myLocationEnabled: true,
                  myLocationButtonEnabled: true,
                ),
                if (!widget.readOnly)
                  Positioned(
                    top: 10,
                    left: 10,
                    right: 100,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      color: Colors.black54,
                      child: const Text(
                        'Tap to add checkpoints in order ',
                        style: TextStyle(color: Colors.white),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (!widget.readOnly)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _saveRace,
                  style:
                      ElevatedButton.styleFrom(backgroundColor: Colors.black),
                  child: Text(widget.raceId != null
                    ? 'UPDATE RACE'
                    : 'SAVE & CREATE RACE'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
