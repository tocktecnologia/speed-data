import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:speed_data/features/models/competitor_model.dart';
import 'package:speed_data/features/models/race_session_model.dart';
import 'package:speed_data/features/services/firestore_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:speed_data/features/widgets/track_shape_widget.dart';

class AdminMapView extends StatefulWidget {
  final String raceId;
  final String? eventId;
  final String? sessionId;
  final String raceName;
  final SessionType sessionType;

  const AdminMapView({
    Key? key,
    required this.raceId,
    this.eventId,
    this.sessionId,
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
  StreamSubscription<QuerySnapshot>? _participantsSubscription;
  StreamSubscription<List<Competitor>>? _competitorsSubscription;
  Map<String, LatLng> _pilotPositions = {};
  Map<String, String> _pilotLabels = {};
  Map<String, String> _competitorLabels = {};
  Map<String, Map<String, dynamic>> _participantMetadata = {};

  static const List<Color> _pilotColors = [
    Colors.cyan,
    Colors.amber,
    Colors.orangeAccent,
    Colors.lightGreen,
    Colors.deepPurple,
    Colors.pink,
    Colors.tealAccent,
  ];

  @override
  void initState() {
    super.initState();
    _loadRaceData();
    _subscribeCompetitors();
    _subscribeParticipants();
  }

  @override
  void didUpdateWidget(covariant AdminMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.eventId != widget.eventId ||
        oldWidget.sessionId != widget.sessionId ||
        oldWidget.raceId != widget.raceId) {
      _subscribeParticipants();
    }
  }

  Color _pilotColor(String uid) {
    if (uid.isEmpty) return Colors.cyan;
    final hash = uid.codeUnits.fold(0, (prev, element) => prev + element);
    final index = hash % _pilotColors.length;
    return _pilotColors[index];
  }

  Future<void> _subscribeCompetitors() async {
    String? resolvedEventId = widget.eventId;
    if (resolvedEventId == null || resolvedEventId.isEmpty) {
      final event =
          await _firestoreService.getActiveEventForTrack(widget.raceId);
      resolvedEventId = event?.id;
    }
    if (resolvedEventId == null || resolvedEventId.isEmpty) return;

    _competitorsSubscription?.cancel();
    _competitorsSubscription = _firestoreService
        .getCompetitorsStream(resolvedEventId)
        .listen((competitors) {
      final labels = <String, String>{};
      for (final competitor in competitors) {
        if (competitor.uid.isEmpty) continue;
        final name = competitor.name.trim();
        final number = competitor.number.trim();
        final namePart = name.isNotEmpty ? name : 'Pilot';
        labels[competitor.uid] =
            number.isNotEmpty ? '#$number $namePart' : namePart;
      }
      if (!mounted) return;
      setState(() {
        _competitorLabels = labels;
        _pilotLabels =
            _buildPilotLabels(_pilotPositions.keys, _participantMetadata);
      });
    });
  }

  Map<String, String> _buildPilotLabels(
    Iterable<String> uids,
    Map<String, Map<String, dynamic>> metadataByUid,
  ) {
    final labels = <String, String>{};
    for (final uid in uids) {
      final metadata = metadataByUid[uid] ?? const <String, dynamic>{};
      labels[uid] = _resolvePilotLabel(uid, metadata);
    }
    return labels;
  }

  String _resolvePilotLabel(String uid, Map<String, dynamic> data) {
    final fromCompetitor = _competitorLabels[uid];
    if (fromCompetitor != null && fromCompetitor.isNotEmpty) {
      return fromCompetitor;
    }

    final name = (data['display_name'] as String?)?.trim();
    final numberRaw = data['car_number'] ?? data['number'];
    final number = numberRaw is String ? numberRaw.trim() : '';

    if (number.isNotEmpty && name != null && name.isNotEmpty) {
      return '#$number $name';
    }
    if (name != null && name.isNotEmpty) {
      return name;
    }
    if (number.isNotEmpty) {
      return '#$number';
    }
    return uid.substring(0, math.min(4, uid.length));
  }

  void _subscribeParticipants() {
    _participantsSubscription?.cancel();
    _participantsSubscription = _firestoreService
        .getRaceLocations(
      widget.raceId,
      eventId: widget.eventId,
      sessionId: widget.sessionId,
    )
        .listen((snapshot) {
      final positions = <String, LatLng>{};
      final metadataByUid = <String, Map<String, dynamic>>{};
      for (var doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final current = data['current'] as Map<String, dynamic>?;
        final lat = (current?['lat'] as num?)?.toDouble();
        final lng = (current?['lng'] as num?)?.toDouble();
        if (lat == null || lng == null || (lat == 0.0 && lng == 0.0)) continue;
        positions[doc.id] = LatLng(lat, lng);
        metadataByUid[doc.id] = data;
      }
      if (!mounted) return;
      setState(() {
        _pilotPositions = positions;
        _participantMetadata = metadataByUid;
        _pilotLabels = _buildPilotLabels(positions.keys, metadataByUid);
      });
    });
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
  void dispose() {
    _participantsSubscription?.cancel();
    _competitorsSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
          child: CircularProgressIndicator(color: Colors.white));
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
          pilotPositions: _buildPilotPositions(),
        ),
      ),
    );
  }

  List<PilotPosition> _buildPilotPositions() {
    final positions = <PilotPosition>[];
    _pilotPositions.forEach((uid, location) {
      positions.add(PilotPosition(
        uid: uid,
        location: location,
        color: _pilotColor(uid),
        label: _pilotLabels[uid] ?? uid.substring(0, math.min(4, uid.length)),
      ));
    });
    return positions;
  }
}
