import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

class GpsTestScreen extends StatefulWidget {
  const GpsTestScreen({Key? key}) : super(key: key);

  @override
  State<GpsTestScreen> createState() => _GpsTestScreenState();
}

class _GpsTestScreenState extends State<GpsTestScreen> {
  StreamSubscription<Position>? _positionStreamSubscription;
  final List<Map<String, dynamic>> _pointsBuffer = [];
  Timer? _logTimer;
  bool _isRecording = false;
  double _currentSpeed = 0.0;
  int _pointsCount = 0;

  @override
  void dispose() {
    _stopRecording();
    super.dispose();
  }

  void _startRecording() async {
    if (_isRecording) return;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        // Handle permission denied
        debugPrint('Location permissions are denied');
        return;
      }
    }

    setState(() {
      _isRecording = true;
      _pointsBuffer.clear();
      _currentSpeed = 0.0;
      _pointsCount = 0;
    });

    late LocationSettings locationSettings;
    if (defaultTargetPlatform == TargetPlatform.android) {
      locationSettings = AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
        forceLocationManager: false,
        // Request updates as fast as possible (e.g. 50ms) to try and get >1Hz
        intervalDuration: const Duration(milliseconds: 50),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: "GPS Test Running",
          notificationText: "Background tracking is active",
          enableWakeLock: true,
        ),
      );
    } else if (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      locationSettings = AppleSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        activityType: ActivityType.fitness,
        distanceFilter: 0,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: true,
      );
    } else {
      locationSettings = const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
      );
    }

    _positionStreamSubscription =
        Geolocator.getPositionStream(locationSettings: locationSettings)
            .listen((Position position) {
      setState(() {
        _currentSpeed = position.speed; // Speed in m/s
        _pointsCount++;
      });

      final point = {
        'lat': position.latitude,
        'lng': position.longitude,
        'speed': position.speed,
        'timestamp': position.timestamp.toIso8601String(),
      };

      // Store in list
      _pointsBuffer.add(point);
    });

    // Timer to log and clear buffer every second
    _logTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_pointsBuffer.isNotEmpty) {
        print(
            '\n--- GPS Capture Log (${DateTime.now().toIso8601String()}) ---');
        print('Captured ${_pointsBuffer.length} points in the last second:');
        for (var p in _pointsBuffer) {
          print(p);
        }
        _pointsBuffer.clear();
      } else {
        print(
            '\n--- GPS Capture Log (${DateTime.now().toIso8601String()}) ---');
        print('No points captured in the last second.');
      }
    });
  }

  void _stopRecording() {
    _positionStreamSubscription?.cancel();
    _positionStreamSubscription = null;
    _logTimer?.cancel();
    _logTimer = null;
    setState(() {
      _isRecording = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('GPS Acquisition Test'),
        backgroundColor: Colors.black,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Speed Display
            Text(
              'Speed',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            Text(
              '${(_currentSpeed * 3.6).toStringAsFixed(2)} km/h', // Convert m/s to km/h
              style: const TextStyle(
                fontSize: 48,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            Text('Points Captured: $_pointsCount'),
            const SizedBox(height: 48),

            // Start/Stop Buttons
            if (!_isRecording)
              ElevatedButton(
                onPressed: _startRecording,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
                ),
                child: const Text('START',
                    style: TextStyle(fontSize: 24, color: Colors.white)),
              )
            else
              ElevatedButton(
                onPressed: _stopRecording,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
                ),
                child: const Text('FINISH',
                    style: TextStyle(fontSize: 24, color: Colors.white)),
              ),
          ],
        ),
      ),
    );
  }
}
