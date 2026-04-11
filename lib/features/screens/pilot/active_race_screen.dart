import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
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
  bool _simulationPausedByUser = false;
  bool _localTimingMode = true;
  bool _localTimingConfigLoaded = true;
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
  StreamSubscription<Map<String, dynamic>?>? _pilotAlertSubscription;
  bool _sessionStreamConnected = false;
  bool _pilotAlertStreamConnected = false;
  String? _sessionStreamError;
  String? _pilotAlertStreamError;
  Color _sessionBackgroundColor = Colors.black;
  LiveTimerMode _mode = LiveTimerMode.simple;
  GaugeType _gaugeType = GaugeType.speed;
  Timer? _uiTimer;
  Timer? _pilotAlertBlinkTimer;
  bool _pilotAlertBlinkVisible = true;
  String? _pilotAlertEventId;
  String? _pilotAlertSessionId;
  Map<String, dynamic>? _pilotAlertPayload;
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

  void _debugLog(String message) {
    if (!kDebugMode) return;
    final ts = DateTime.now().toIso8601String();
    debugPrint(
      '[ActiveRaceScreen][$ts][race:${widget.raceId}]'
      '[event:${_currentEventId ?? widget.eventId ?? '-'}]'
      '[session:${_activeSession?.id ?? '-'}]'
      '[uid:$_effectiveUserId] $message',
    );
  }

  String _sessionDebug(RaceSession? session) {
    if (session == null) return 'null';
    return 'id=${session.id}, status=${session.status.name}, '
        'flag=${session.currentFlag.name}, '
        'scheduled=${session.scheduledTime.toIso8601String()}, '
        'actualStart=${session.actualStartTime?.toIso8601String()}';
  }

  @override
  void initState() {
    super.initState();
    _telemetryService = TelemetryService.instance;
    _debugLog(
      'initState: raceName=${widget.raceName}, eventIdParam=${widget.eventId}, '
      'authUid=${FirebaseAuth.instance.currentUser?.uid}, '
      'authEmail=${FirebaseAuth.instance.currentUser?.email}',
    );

    _loadSimulationModeConfig();
    _loadLocalTimingModeConfig();
    _loadRaceDetails();
    _startUiTimer();
  }

  @override
  void dispose() {
    _debugLog('dispose');
    _statusSubscription?.cancel(); // Cancel subscription on dispose
    _pilotAlertSubscription?.cancel();
    _uiTimer?.cancel();
    _pilotAlertBlinkTimer?.cancel();
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

  List<LatLng> _parseRoutePath(dynamic rawRoutePath) {
    if (rawRoutePath is! List || rawRoutePath.isEmpty) return const [];
    final points = <LatLng>[];
    for (final item in rawRoutePath) {
      if (item is! Map) continue;
      final dynamic latRaw = item['lat'];
      final dynamic lngRaw = item['lng'];
      if (latRaw is num && lngRaw is num) {
        points.add(LatLng(latRaw.toDouble(), lngRaw.toDouble()));
      }
    }
    return points;
  }

  Future<bool> _applyRaceData(Map<String, dynamic> data,
      {required String source}) async {
    final checkpointsRaw = data['checkpoints'] as List<dynamic>?;
    final savedRoutePathRaw = data['route_path'] as List<dynamic>?;
    _debugLog(
      '_applyRaceData($source): checkpoints=${checkpointsRaw?.length ?? 0}, '
      'routePathSaved=${savedRoutePathRaw?.length ?? 0}',
    );

    if (checkpointsRaw == null || checkpointsRaw.isEmpty) {
      final routeOnly = _parseRoutePath(savedRoutePathRaw);
      if (routeOnly.length > 1 && mounted) {
        setState(() {
          _routePath = routeOnly;
          _polylines = {
            Polyline(
              polylineId: const PolylineId('race_route'),
              points: routeOnly,
              color: Colors.blue,
              width: 5,
            ),
          };
          _raceMarkers = {};
        });
        _debugLog(
          '_applyRaceData($source): loaded route-only path (${routeOnly.length} points)',
        );
        await _maybeAutoStartSimulation();
        return true;
      }
      _debugLog('_applyRaceData($source): no checkpoints/route to apply');
      return false;
    }

    final checkpoints = checkpointsRaw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList(growable: false);
    if (checkpoints.isEmpty) {
      _debugLog('_applyRaceData($source): checkpoints list parsed empty');
      return false;
    }
    _checkpoints = checkpoints;
    _telemetryService.setCheckpoints(_checkpoints);

    final firstPoint = checkpoints.first;
    final firstLatRaw = firstPoint['lat'];
    final firstLngRaw = firstPoint['lng'];
    if (firstLatRaw is num && firstLngRaw is num) {
      _startLocation = LatLng(firstLatRaw.toDouble(), firstLngRaw.toDouble());
      if (_mapController != null && mounted) {
        _mapController!
            .animateCamera(CameraUpdate.newLatLngZoom(_startLocation!, 16));
        _isInitLocationSet = true;
      }
    }

    final straightRoutePoints = <LatLng>[];
    final markerDefs = <({int index, LatLng position, String label})>[];
    for (int i = 0; i < checkpoints.length; i++) {
      final point = checkpoints[i];
      final latRaw = point['lat'];
      final lngRaw = point['lng'];
      if (latRaw is! num || lngRaw is! num) continue;
      final lat = latRaw.toDouble();
      final lng = lngRaw.toDouble();

      if (i == checkpoints.length - 1 && checkpoints.length > 1) {
        final first = checkpoints.first;
        final fLatRaw = first['lat'];
        final fLngRaw = first['lng'];
        if (fLatRaw is num &&
            fLngRaw is num &&
            (lat - fLatRaw.toDouble()).abs() < 0.000001 &&
            (lng - fLngRaw.toDouble()).abs() < 0.000001) {
          continue;
        }
      }

      final position = LatLng(lat, lng);
      straightRoutePoints.add(position);
      markerDefs.add((
        index: i,
        position: position,
        label: String.fromCharCode(65 + i),
      ));
    }

    List<LatLng> finalRoutePoints = straightRoutePoints;
    final savedRoutePath = _parseRoutePath(savedRoutePathRaw);
    if (savedRoutePath.isNotEmpty) {
      finalRoutePoints = savedRoutePath;
    }

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
        _routePath = finalRoutePoints;
        _polylines = polylines;
      });
    }
    _debugLog(
      '_applyRaceData($source): route prepared with ${finalRoutePoints.length} points; '
      'markersPending=${markerDefs.length}',
    );
    await _maybeAutoStartSimulation();

    if (markerDefs.isEmpty) {
      if (mounted) {
        setState(() {
          _raceMarkers = {};
        });
      }
      return finalRoutePoints.isNotEmpty;
    }

    try {
      final markerList = await Future.wait(
        markerDefs.map((entry) async {
          final icon = await createCustomMarkerBitmap(
            entry.label,
            color: entry.index == 0 ? Colors.green : Colors.blue,
          );
          return Marker(
            markerId: MarkerId('checkpoint_${entry.index}'),
            position: entry.position,
            infoWindow: InfoWindow(title: 'Checkpoint ${entry.label}'),
            icon: icon,
          );
        }),
      );
      if (mounted) {
        setState(() {
          _raceMarkers = markerList.toSet();
        });
      }
      _debugLog('_applyRaceData($source): markers ready=${markerList.length}');
    } catch (e, st) {
      _debugLog('_applyRaceData($source): marker generation failed: $e\n$st');
    }

    return finalRoutePoints.isNotEmpty || checkpoints.isNotEmpty;
  }

  Future<void> _loadUserColorAsync() async {
    _debugLog('_loadUserColorAsync: start');
    try {
      final userProfile =
          await _firestoreService.getUserProfile(_effectiveUserId);
      if (userProfile != null && userProfile.containsKey('color')) {
        final colorData = userProfile['color'];
        Color? parsedColor;
        if (colorData is int) {
          parsedColor = Color(colorData);
        } else if (colorData is String) {
          final parsed = int.tryParse(colorData);
          if (parsed != null) {
            parsedColor = Color(parsed);
          }
        }
        if (parsedColor != null && mounted) {
          setState(() {
            _userColor = parsedColor!;
          });
        }
      }
      _debugLog('_loadUserColorAsync: done');
    } catch (e, st) {
      _debugLog('_loadUserColorAsync: failed: $e\n$st');
    }
  }

  Future<void> _loadRaceDetails() async {
    _debugLog('_loadRaceDetails: start');
    final stream = _firestoreService.getRaceStream(widget.raceId);
    final raceFirstSnapshotFuture = stream.first;
    late Future<void> Function() recoverActiveSessionBinding;

    Future<void> attachEventListeners(String eventId) async {
      _debugLog('attachEventListeners: eventId=$eventId');
      if (!mounted) return;
      setState(() => _currentEventId = eventId);
      await _loadPilotIdentityForEvent(eventId);

      // Preload current event state to avoid long "waiting active session" gaps
      // when entering/re-entering this screen on slower mobile links.
      try {
        final RaceEvent? event =
            await _firestoreService.getEvent(eventId, forceServer: true);
        _debugLog(
          'attachEventListeners: preload event from server -> '
          '${event == null ? 'null' : 'id=${event.id}, trackId=${event.trackId}, sessions=${event.sessions.length}'}',
        );
        if (event != null && event.trackId != widget.raceId) {
          _debugLog(
            'attachEventListeners: WARNING track mismatch '
            '(event.trackId=${event.trackId}, widget.raceId=${widget.raceId})',
          );
        }
        if (event != null) {
          RaceSession? preloadedSession;
          try {
            preloadedSession = event.sessions.firstWhere(
              (s) => s.status == SessionStatus.active,
            );
          } catch (_) {
            preloadedSession = null;
          }
          _debugLog(
            'attachEventListeners: preloaded active session -> ${_sessionDebug(preloadedSession)}',
          );
          await _applySessionState(preloadedSession);
        }
      } catch (e, st) {
        _debugLog('attachEventListeners: preload failed: $e\n$st');
      }

      _statusSubscription?.cancel();
      _debugLog('attachEventListeners: subscribed getEventActiveSessionStream');
      if (mounted) {
        setState(() {
          _sessionStreamConnected = false;
          _sessionStreamError = null;
        });
      }
      _statusSubscription = _firestoreService
          .getEventActiveSessionStream(eventId)
          .listen((session) async {
        _debugLog(
            'eventActiveSessionStream: update -> ${_sessionDebug(session)}');
        if (mounted &&
            (!_sessionStreamConnected || _sessionStreamError != null)) {
          setState(() {
            _sessionStreamConnected = true;
            _sessionStreamError = null;
          });
        }
        await _applySessionState(session);
        if (session == null) {
          _debugLog(
            'eventActiveSessionStream: session null, scheduling recoverActiveSessionBinding',
          );
          unawaited(recoverActiveSessionBinding());
        }
      }, onError: (error, stackTrace) {
        _debugLog('eventActiveSessionStream: error -> $error');
        if (!mounted) return;
        setState(() {
          _sessionStreamConnected = false;
          _sessionStreamError = '$error';
        });
      }, onDone: () {
        _debugLog('eventActiveSessionStream: done');
        if (!mounted) return;
        setState(() {
          _sessionStreamConnected = false;
        });
      });
    }

    recoverActiveSessionBinding = () async {
      _debugLog('recoverActiveSessionBinding: scheduled in 2s');
      await Future.delayed(const Duration(seconds: 2));
      if (!mounted) {
        _debugLog('recoverActiveSessionBinding: aborted (unmounted)');
        return;
      }
      if (_activeSession != null) {
        _debugLog(
          'recoverActiveSessionBinding: aborted (already has active session ${_activeSession!.id})',
        );
        return;
      }

      try {
        _debugLog(
            'recoverActiveSessionBinding: querying active event for track');
        final event = await _firestoreService.getActiveEventForTrack(
          widget.raceId,
          allowFallback: true,
          requireActiveSession: true,
          forceServer: true,
        );
        if (!mounted) {
          _debugLog('recoverActiveSessionBinding: unmounted after query');
          return;
        }
        if (event == null) {
          _debugLog('recoverActiveSessionBinding: no active event found');
          return;
        }
        _debugLog(
          'recoverActiveSessionBinding: got event id=${event.id}, sessions=${event.sessions.length}',
        );

        if (_currentEventId != event.id) {
          _debugLog(
            'recoverActiveSessionBinding: switching event binding $_currentEventId -> ${event.id}',
          );
          await attachEventListeners(event.id);
          return;
        }

        try {
          final session = event.sessions
              .firstWhere((s) => s.status == SessionStatus.active);
          _debugLog(
            'recoverActiveSessionBinding: applying active session -> ${_sessionDebug(session)}',
          );
          await _applySessionState(session);
        } catch (e) {
          _debugLog(
              'recoverActiveSessionBinding: event has no active session ($e)');
        }
      } catch (e, st) {
        _debugLog('recoverActiveSessionBinding: failed: $e\n$st');
      }
    };

    if (widget.eventId != null && widget.eventId!.isNotEmpty) {
      _debugLog(
        '_loadRaceDetails: using explicit widget.eventId=${widget.eventId}',
      );
      await attachEventListeners(widget.eventId!);
      unawaited(recoverActiveSessionBinding());
    } else {
      () async {
        _debugLog('_loadRaceDetails: resolving eventId by track');
        final activeEvent = await _firestoreService.getActiveEventForTrack(
          widget.raceId,
          allowFallback: true,
          requireActiveSession: true,
          forceServer: true,
        );
        _debugLog(
          '_loadRaceDetails: activeEvent(requireActiveSession=true) -> '
          '${activeEvent?.id ?? 'null'}',
        );
        final event = activeEvent ??
            await _firestoreService.getActiveEventForTrack(
              widget.raceId,
              allowFallback: true,
              requireActiveSession: false,
            );
        _debugLog(
          '_loadRaceDetails: selected event after fallback -> ${event?.id ?? 'null'}',
        );
        if (!mounted) return;
        if (event == null) {
          _debugLog('_loadRaceDetails: no event found, applying null session');
          await _applySessionState(null);
          return;
        }
        await attachEventListeners(event.id);
        unawaited(recoverActiveSessionBinding());
      }()
          .catchError((e, st) {
        _debugLog('_loadRaceDetails: resolve event failed: $e\n$st');
      });
    }

    final snapshot = await raceFirstSnapshotFuture;
    _debugLog(
      '_loadRaceDetails: race stream first snapshot exists=${snapshot.exists}',
    );
    final snapData = snapshot.data();
    if (snapData is Map) {
      _debugLog(
        '_loadRaceDetails: race snapshot keys=${Map<String, dynamic>.from(snapData).keys.toList()}',
      );
    } else {
      _debugLog(
        '_loadRaceDetails: race snapshot data type=${snapData.runtimeType}',
      );
    }

    // Non-critical: do not block race route/checkpoints load.
    unawaited(_loadUserColorAsync());

    bool raceApplied = false;
    if (snapshot.exists && snapshot.data() is Map) {
      raceApplied = await _applyRaceData(
        Map<String, dynamic>.from(snapshot.data() as Map),
        source: 'stream_first',
      );
    }

    if (!raceApplied) {
      try {
        _debugLog(
          '_loadRaceDetails: race data incomplete from first snapshot, trying server fallback',
        );
        final serverRace =
            await _firestoreService.getRace(widget.raceId, forceServer: true);
        if (serverRace != null) {
          raceApplied = await _applyRaceData(
            serverRace,
            source: 'server_fallback',
          );
        } else {
          _debugLog('_loadRaceDetails: server fallback returned null race');
        }
      } catch (e, st) {
        _debugLog('_loadRaceDetails: server fallback failed: $e\n$st');
      }
    }

    if (!raceApplied) {
      _debugLog('_loadRaceDetails: race data could not be resolved yet');
    }
  }

  Future<void> _applySessionState(RaceSession? session) async {
    if (!mounted) return;
    _debugLog(
      '_applySessionState: incoming=${_sessionDebug(session)}, '
      'previous=${_sessionDebug(_activeSession)}, '
      'autoSimulationMode=$_autoSimulationMode, '
      'simulationConfigLoaded=$_simulationConfigLoaded, '
      'localTimingMode=$_localTimingMode, '
      'isSimulating=${_telemetryService.isSimulating}, '
      'isRecording=${_telemetryService.isRecording}',
    );
    final shouldRestartSimulation = session != null &&
        _telemetryService.isSimulating &&
        _telemetryService.currentSessionId != session.id;
    if (shouldRestartSimulation) {
      _debugLog(
        '_applySessionState: restarting simulation due session change '
        '${_telemetryService.currentSessionId} -> ${session.id}',
      );
      await _stopSimulation(markPausedByUser: false);
      _autoStartedSimulationSessionId = null;
    }

    final previousSessionId = _activeSession?.id;
    final sessionTimelines = session == null
        ? const <Map<String, dynamic>>[]
        : session.timelines
            .map((timeline) => timeline.toMap())
            .toList(growable: false);
    final minLapSeconds = session?.minLapTimeSeconds ?? 0;
    setState(() {
      _activeSession = session;
      if (session != null) {
        if (previousSessionId != session.id) {
          _localLapStartMs = _resolveSafeSessionStartMs(session);
          _simulationPausedByUser = false;
        }
        _telemetryService.setSessionId(session.id);
        _telemetryService.setTimelines(sessionTimelines);
        _telemetryService.setLocalTimingMinLapSeconds(minLapSeconds);
        if (_autoSimulationMode) {
          _telemetryService.enableSendDataToCloud = false;
        } else if (!_telemetryService.isSimulating) {
          _telemetryService.enableSendDataToCloud = true;
          if (!_telemetryService.isRecording) {
            _debugLog(
              '_applySessionState: startRecording(race=${widget.raceId}, '
              'event=$_currentEventId, session=${session.id})',
            );
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
        _simulationPausedByUser = false;
        _telemetryService.setSessionId(null);
        _telemetryService.setTimelines(sessionTimelines);
        _telemetryService.setLocalTimingMinLapSeconds(minLapSeconds);
        _telemetryService.enableSendDataToCloud = false;
        _sessionBackgroundColor = Colors.black;
      }
    });
    _debugLog(
      '_applySessionState: applied activeSession=${_activeSession?.id ?? 'null'}, '
      'sendToCloud=${_telemetryService.enableSendDataToCloud}, '
      'sessionIdInTelemetry=${_telemetryService.currentSessionId}',
    );
    _syncPilotAlertSubscription();
    await _maybeAutoStartSimulation();
  }

  void _clearPilotAlertState() {
    _pilotAlertBlinkTimer?.cancel();
    _pilotAlertBlinkTimer = null;
    if (!mounted) return;
    setState(() {
      _pilotAlertPayload = null;
      _pilotAlertBlinkVisible = true;
    });
  }

  void _startPilotAlertBlinking() {
    if (_pilotAlertBlinkTimer != null) return;
    _pilotAlertBlinkTimer =
        Timer.periodic(const Duration(milliseconds: 450), (_) {
      if (!mounted) return;
      setState(() => _pilotAlertBlinkVisible = !_pilotAlertBlinkVisible);
    });
  }

  void _syncPilotAlertSubscription() {
    final eventId = _currentEventId;
    final sessionId = _activeSession?.id;
    final pilotUid = _effectiveUserId;
    final canListen = eventId != null &&
        eventId.isNotEmpty &&
        sessionId != null &&
        sessionId.isNotEmpty &&
        pilotUid.isNotEmpty;

    if (!canListen) {
      _pilotAlertSubscription?.cancel();
      _pilotAlertSubscription = null;
      _pilotAlertEventId = null;
      _pilotAlertSessionId = null;
      if (mounted) {
        setState(() {
          _pilotAlertStreamConnected = false;
          _pilotAlertStreamError = null;
        });
      }
      _clearPilotAlertState();
      return;
    }

    if (_pilotAlertSubscription != null &&
        _pilotAlertEventId == eventId &&
        _pilotAlertSessionId == sessionId) {
      return;
    }

    _pilotAlertSubscription?.cancel();
    _pilotAlertEventId = eventId;
    _pilotAlertSessionId = sessionId;
    if (mounted) {
      setState(() {
        _pilotAlertStreamConnected = false;
        _pilotAlertStreamError = null;
      });
    }
    _pilotAlertSubscription = _firestoreService
        .getPilotAlertStream(
      eventId: eventId!,
      sessionId: sessionId!,
      pilotUid: pilotUid,
    )
        .listen((alert) {
      if (!mounted) return;
      if (!_pilotAlertStreamConnected || _pilotAlertStreamError != null) {
        setState(() {
          _pilotAlertStreamConnected = true;
          _pilotAlertStreamError = null;
        });
      }
      final rawMessage = (alert?['message'] as String?)?.trim() ?? '';
      final active = alert?['active'] == true && rawMessage.isNotEmpty;
      final expiresAtMs = alert?['expires_at_ms'];
      bool expired = false;
      if (expiresAtMs is num) {
        expired = DateTime.now().millisecondsSinceEpoch > expiresAtMs.toInt();
      }

      if (!active || expired) {
        _clearPilotAlertState();
        return;
      }

      setState(() {
        _pilotAlertPayload = alert;
        _pilotAlertBlinkVisible = true;
      });
      _startPilotAlertBlinking();
    }, onError: (error, stackTrace) {
      _debugLog('pilotAlertStream: error -> $error');
      if (!mounted) return;
      setState(() {
        _pilotAlertStreamConnected = false;
        _pilotAlertStreamError = '$error';
      });
      _clearPilotAlertState();
    }, onDone: () {
      _debugLog('pilotAlertStream: done');
      if (!mounted) return;
      setState(() {
        _pilotAlertStreamConnected = false;
      });
    });
  }

  Widget _buildRealtimeHealthBar() {
    Widget badge({
      required String label,
      required bool connected,
      String? error,
      required IconData icon,
    }) {
      final hasError = error != null && error.trim().isNotEmpty;
      final bgColor = hasError
          ? Colors.red.withValues(alpha: 0.14)
          : connected
              ? Colors.green.withValues(alpha: 0.14)
              : Colors.orange.withValues(alpha: 0.14);
      final borderColor =
          hasError ? Colors.red : (connected ? Colors.green : Colors.orange);
      final textColor = borderColor;
      final statusText = hasError
          ? 'offline'
          : connected
              ? 'online'
              : 'connecting';

      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: textColor),
            const SizedBox(width: 6),
            Text(
              '$label: $statusText',
              style: TextStyle(
                color: textColor,
                fontWeight: FontWeight.w700,
                fontSize: 11,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      color: Colors.black,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        children: [
          badge(
            label: 'Session',
            connected: _sessionStreamConnected,
            error: _sessionStreamError,
            icon: Icons.sync,
          ),
          badge(
            label: 'Alerts',
            connected: _pilotAlertStreamConnected,
            error: _pilotAlertStreamError,
            icon: Icons.notifications_active_outlined,
          ),
        ],
      ),
    );
  }

  Future<void> _loadSimulationModeConfig() async {
    final email = FirebaseAuth.instance.currentUser?.email;
    _debugLog('_loadSimulationModeConfig: start, email=${email ?? 'null'}');
    Map<String, dynamic> config;
    try {
      config = await _firestoreService.getSimulationRuntimeConfig(email: email);
      _debugLog('_loadSimulationModeConfig: raw config=$config');
    } catch (e, st) {
      _debugLog('_loadSimulationModeConfig: failed to load config: $e\n$st');
      if (!mounted) return;
      // Fail safe: avoid keeping the UI in an indefinite loading state.
      setState(() {
        _autoSimulationMode = false;
        _simulationConfigLoaded = true;
        _simulationPausedByUser = false;
      });
      return;
    }
    if (!mounted) return;

    final enabled = config['enabled'] == true;
    final autoStart = config['auto_start'] != false;
    final speedMps = config['speed_mps'] is num
        ? (config['speed_mps'] as num).toDouble()
        : 40.0;

    setState(() {
      _autoSimulationMode = enabled && autoStart;
      _simulationConfigLoaded = true;
      if (!_autoSimulationMode) {
        _simulationPausedByUser = false;
      }
    });
    _debugLog(
      '_loadSimulationModeConfig: resolved autoSimulationMode=$_autoSimulationMode, '
      'simulationConfigLoaded=$_simulationConfigLoaded, speedMps=$speedMps, '
      'source=${config['source']}',
    );
    _telemetryService.setSimulationSpeed(speedMps);

    if (!_autoSimulationMode && _telemetryService.isSimulating) {
      _debugLog(
        '_loadSimulationModeConfig: stopping current simulation because mode disabled',
      );
      await _stopSimulation(markPausedByUser: false);
    }
    await _maybeAutoStartSimulation();
  }

  Future<void> _loadLocalTimingModeConfig() async {
    _debugLog('_loadLocalTimingModeConfig: local timing forced enabled');
    if (!mounted) return;

    setState(() {
      _localTimingMode = true;
      _localTimingConfigLoaded = true;
    });
    _telemetryService.setLocalTimingEnabled(true);

    final minLapSeconds = _activeSession?.minLapTimeSeconds ?? 0;
    _telemetryService.setLocalTimingMinLapSeconds(minLapSeconds);

    _debugLog(
      '_loadLocalTimingModeConfig: resolved localTimingMode=$_localTimingMode, '
      'localTimingConfigLoaded=$_localTimingConfigLoaded',
    );
  }

  Future<void> _maybeAutoStartSimulation() async {
    if (!_simulationConfigLoaded || !_autoSimulationMode) {
      _debugLog(
        '_maybeAutoStartSimulation: skip (simulationConfigLoaded=$_simulationConfigLoaded, '
        'autoSimulationMode=$_autoSimulationMode)',
      );
      return;
    }
    if (_simulationPausedByUser) {
      _debugLog('_maybeAutoStartSimulation: skip (paused by user)');
      return;
    }
    if (_activeSession == null || _activeSession!.id.isEmpty) {
      _debugLog('_maybeAutoStartSimulation: skip (no active session)');
      return;
    }
    if (_routePath.isEmpty) {
      _debugLog('_maybeAutoStartSimulation: skip (routePath empty)');
      return;
    }
    if (_telemetryService.isSimulating &&
        _telemetryService.currentSessionId != _activeSession!.id) {
      _debugLog(
        '_maybeAutoStartSimulation: stop stale simulation '
        '${_telemetryService.currentSessionId} -> ${_activeSession!.id}',
      );
      await _stopSimulation(markPausedByUser: false);
      _autoStartedSimulationSessionId = null;
    }
    try {
      _debugLog(
        '_maybeAutoStartSimulation: auto start for session=${_activeSession!.id}',
      );
      await _startSimulation(auto: true);
    } catch (e, st) {
      _debugLog('_maybeAutoStartSimulation: auto start failed: $e\n$st');
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
    _debugLog('_loadPilotIdentityForEvent: eventId=$eventId');
    try {
      final Competitor? competitor =
          await _firestoreService.getCompetitorByUid(eventId, _effectiveUserId);
      if (!mounted) return;
      setState(() {
        _pilotCompetitorId = competitor?.id;
        _pilotCarNumber = competitor?.number.trim();
        _pilotDriverName = competitor?.name.trim();
      });
      _debugLog(
        '_loadPilotIdentityForEvent: competitor='
        '${competitor == null ? 'null' : 'id=${competitor.id}, number=${competitor.number}, name=${competitor.name}, uid=${competitor.uid}'}',
      );
    } catch (e, st) {
      _debugLog('_loadPilotIdentityForEvent: failed: $e\n$st');
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
    _debugLog(
      '_startSimulation: auto=$auto, activeSession=${_activeSession?.id}, '
      'routePoints=${_routePath.length}, isSimulating=${_telemetryService.isSimulating}, '
      'currentSimSession=${_telemetryService.currentSessionId}',
    );
    if (_activeSession == null || _activeSession!.id.isEmpty) {
      if (!auto && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No active session to simulate')));
      }
      _debugLog('_startSimulation: aborted (no active session)');
      return;
    }
    if (_routePath.isEmpty) {
      if (!auto && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No route path available')));
      }
      _debugLog('_startSimulation: aborted (route path empty)');
      return;
    }
    if (_telemetryService.isSimulating) {
      if (_telemetryService.currentSessionId == _activeSession!.id) {
        _debugLog('_startSimulation: already simulating same session');
        return;
      }
      await _stopSimulation(markPausedByUser: false);
      _autoStartedSimulationSessionId = null;
    }
    if (auto && _autoStartedSimulationSessionId == _activeSession!.id) return;
    _autoStartedSimulationSessionId = _activeSession!.id;
    final timelines = _activeSession!.timelines
        .map((timeline) => timeline.toMap())
        .toList(growable: false);
    try {
      await _telemetryService.startSimulation(
        routePath: _routePath,
        checkpoints: _checkpoints,
        raceId: widget.raceId,
        userId: _effectiveUserId,
        sessionId: _activeSession!.id,
        eventId: _currentEventId,
        timelines: timelines,
      );
      if (mounted && _simulationPausedByUser) {
        setState(() {
          _simulationPausedByUser = false;
        });
      }
      _debugLog('_startSimulation: started successfully');
    } catch (_) {
      _autoStartedSimulationSessionId = null;
      _debugLog('_startSimulation: failed');
      rethrow;
    }
  }

  Future<void> _stopSimulation({required bool markPausedByUser}) async {
    _debugLog(
      '_stopSimulation: requested markPausedByUser=$markPausedByUser, '
      'isSimulating=${_telemetryService.isSimulating}',
    );
    if (!_telemetryService.isSimulating) {
      if (mounted && _simulationPausedByUser != markPausedByUser) {
        setState(() {
          _simulationPausedByUser = markPausedByUser;
        });
      }
      _debugLog('_stopSimulation: no-op (not simulating)');
      return;
    }

    await _telemetryService.stopSimulation();
    _autoStartedSimulationSessionId = null;

    // In simulation mode, pausing should not fall back to real GPS upload.
    if (_autoSimulationMode) {
      _telemetryService.enableSendDataToCloud = false;
      if (_telemetryService.isRecording) {
        await _telemetryService.stopRecording();
        if (_activeSession != null) {
          _telemetryService.setSessionId(_activeSession!.id);
        }
      }
    }

    if (mounted) {
      setState(() {
        _simulationPausedByUser = markPausedByUser;
      });
    }
    _debugLog(
      '_stopSimulation: completed, pausedByUser=$_simulationPausedByUser, '
      'sendToCloud=${_telemetryService.enableSendDataToCloud}',
    );
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

  Widget _buildTimingContent({
    required TelemetryService telemetry,
    required String? sessionId,
  }) {
    if (_localTimingMode && telemetry.localTimingEnabled) {
      final bestLapMs = telemetry.localBestLapMs;
      final previousLapMs = telemetry.localPreviousLapMs;
      final currentLapMs = telemetry.localCurrentLapMs;

      final best = bestLapMs != null ? _formatLapTime(bestLapMs) : '--:--.---';
      final previous =
          previousLapMs != null ? _formatLapTime(previousLapMs) : '--:--.---';
      final current =
          currentLapMs != null ? _formatLapTime(currentLapMs) : '--:--.---';

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
    }

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

    return StreamBuilder<QuerySnapshot>(
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

        final minLapMs = (_activeSession?.minLapTimeSeconds ?? 0) * 1000;
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

            final passings = passingSnapshot.data ?? const <PassingModel>[];
            final completedLapTimes = <int>[];
            int? latestLapCloseTs;

            for (final passing in passings) {
              if (!_isCurrentPilotPassing(passing)) {
                continue;
              }
              final flags = passing.flags.map((f) => f.toLowerCase()).toSet();
              if (flags.contains('invalid') || flags.contains('deleted')) {
                continue;
              }

              final lapMs = passing.lapTime?.round();
              if (lapMs == null || lapMs <= 0) {
                continue;
              }
              if (minLapMs > 0 && lapMs < minLapMs) {
                continue;
              }

              final ts = passing.timestamp.millisecondsSinceEpoch;
              if (safeSessionStartMs != null &&
                  ts < safeSessionStartMs - 1000) {
                continue;
              }

              if (latestLapCloseTs == null || ts > latestLapCloseTs) {
                latestLapCloseTs = ts;
              }
              completedLapTimes.add(lapMs);
            }

            int? currentLapStartTs;
            if (_activeSession != null) {
              currentLapStartTs = latestLapCloseTs ?? safeSessionStartMs;
            } else {
              currentLapStartTs = latestLapCloseTs ?? _localLapStartMs;
            }

            if (currentLapStartTs != null &&
                _localLapStartMs != currentLapStartTs) {
              _localLapStartMs = currentLapStartTs;
            }

            int? bestLapMs;
            int? previousLapMs;
            if (completedLapTimes.isNotEmpty) {
              previousLapMs = completedLapTimes.last;
              bestLapMs = completedLapTimes.reduce((a, b) => a < b ? a : b);
            }

            int? currentLapMs;
            if (currentLapStartTs != null) {
              final nowMs = _uiNow.millisecondsSinceEpoch;
              final diff = nowMs - currentLapStartTs;
              currentLapMs = diff > 0 ? diff : 0;
            }

            final best =
                bestLapMs != null ? _formatLapTime(bestLapMs) : '--:--.---';
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
    );
  }

  Widget _buildPilotAlertOverlay() {
    final alert = _pilotAlertPayload;
    if (alert == null) return const SizedBox.shrink();

    final message = (alert['message'] as String?)?.trim().toUpperCase();
    if (message == null || message.isEmpty) return const SizedBox.shrink();

    final blinkBackgroundColor =
        _pilotAlertBlinkVisible ? SpeedDataTheme.flagPurple : Colors.black;

    return IgnorePointer(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        color: blinkBackgroundColor,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'ALERTA DA EQUIPE',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: 12),
                FractionallySizedBox(
                  widthFactor: 0.8,
                  child: FittedBox(
                    fit: BoxFit.fitWidth,
                    child: Text(
                      message,
                      maxLines: 1,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 180,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2.5,
                        height: 1.0,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
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
            final authUser = FirebaseAuth.instance.currentUser;
            final pilotName = (_pilotDriverName?.trim().isNotEmpty ?? false)
                ? _pilotDriverName!.trim()
                : ((authUser?.displayName?.trim().isNotEmpty ?? false)
                    ? authUser!.displayName!.trim()
                    : (authUser?.email?.trim().isNotEmpty ?? false)
                        ? authUser!.email!.trim()
                        : 'Pilot');

            final borderColor = _activeSession != null
                ? _getFlagColor(_activeSession!.currentFlag)
                : Colors.transparent;

            return Stack(
              children: [
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: borderColor, width: 4),
                  ),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
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
                            const SizedBox(height: 4),
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
                      _buildRealtimeHealthBar(),
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
                        child: _buildTimingContent(
                          telemetry: telemetry,
                          sessionId: sessionId,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.all(12),
                        color: Colors.black,
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.timer,
                                  color: telemetry.localTimingEnabled
                                      ? Colors.amberAccent
                                      : Colors.white54,
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    telemetry.localTimingEnabled
                                        ? 'Local timing ativo no dispositivo (Fase 1).'
                                        : (_localTimingConfigLoaded
                                            ? 'Local timing desativado para este usuario.'
                                            : 'Loading local timing config...'),
                                    style: TextStyle(
                                      color: telemetry.localTimingEnabled
                                          ? Colors.amberAccent
                                          : Colors.white70,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                Column(
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 12, vertical: 6),
                                          decoration: BoxDecoration(
                                            color: _getGpsColor(
                                                    _telemetryService
                                                        .currentFrequency)
                                                .withAlpha(50),
                                            borderRadius:
                                                BorderRadius.circular(20),
                                            border: Border.all(
                                              color: _getGpsColor(
                                                  _telemetryService
                                                      .currentFrequency),
                                            ),
                                          ),
                                          child: Text(
                                            "${_telemetryService.currentFrequency} Hz",
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: _getGpsColor(
                                                  _telemetryService
                                                      .currentFrequency),
                                            ),
                                          ),
                                        )
                                      ],
                                    ),
                                  ],
                                )
                              ],
                            ),
                            const SizedBox(height: 6),
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
                                            ? (_simulationPausedByUser
                                                ? 'Simulation paused by user. Press START to resume.'
                                                : 'Simulation mode enabled. Waiting for active session...')
                                            : (_simulationConfigLoaded
                                                ? 'Simulation mode disabled for this user.'
                                                : 'Loading simulation config...')),
                                    style: const TextStyle(
                                      color: Colors.greenAccent,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 6),
                                  child: Text(
                                    pilotName,
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                )
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
                                        _telemetryService
                                            .setSimulationSpeed(val);
                                      },
                                    ),
                                  ),
                                  Text(
                                      '${_telemetryService.simulationSpeed.toStringAsFixed(1)} m/s',
                                      style: const TextStyle(
                                          color: Colors.white70)),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      onPressed: _telemetryService.isSimulating
                                          ? null
                                          : () async {
                                              try {
                                                await _startSimulation(
                                                    auto: false);
                                                if (mounted) {
                                                  ScaffoldMessenger.of(context)
                                                      .showSnackBar(
                                                    const SnackBar(
                                                      content: Text(
                                                          'Simulation started.'),
                                                    ),
                                                  );
                                                }
                                              } catch (e) {
                                                if (mounted) {
                                                  ScaffoldMessenger.of(context)
                                                      .showSnackBar(
                                                    SnackBar(
                                                      content: Text(
                                                          'Failed to start simulation: $e'),
                                                    ),
                                                  );
                                                }
                                              }
                                            },
                                      icon: const Icon(Icons.play_arrow),
                                      label: const Text('START'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.green,
                                        foregroundColor: Colors.white,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      onPressed: !_telemetryService.isSimulating
                                          ? null
                                          : () async {
                                              await _stopSimulation(
                                                  markPausedByUser: true);
                                              if (mounted) {
                                                ScaffoldMessenger.of(context)
                                                    .showSnackBar(
                                                  const SnackBar(
                                                    content: Text(
                                                        'Simulation paused.'),
                                                  ),
                                                );
                                              }
                                            },
                                      icon: const Icon(Icons.stop),
                                      label: const Text('STOP'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.red,
                                        foregroundColor: Colors.white,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (_pilotAlertPayload != null)
                  Positioned.fill(
                    child: _buildPilotAlertOverlay(),
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
      return Colors.lightGreen;
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
