import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class RouteService {
  // Using the key found in AndroidManifest.xml
  static const String _apiKey = "AIzaSyCiYTEO3l7mEjoxCJNfczspQOh7RGQZtIU";

  Future<List<LatLng>> getRouteBetweenPoints(List<LatLng> points) async {
    if (points.length < 2) return [];

    List<LatLng> routeCoords = [];

    // Initialize with API Key as required by v3.1.0+
    final polylinePoints = PolylinePoints(apiKey: _apiKey);

    for (int i = 0; i < points.length - 1; i++) {
      final start = points[i];
      final end = points[i + 1];

      // Fetch route using request object
      final result = await polylinePoints.getRouteBetweenCoordinates(
          request: PolylineRequest(
        origin: PointLatLng(start.latitude, start.longitude),
        destination: PointLatLng(end.latitude, end.longitude),
        mode: TravelMode.walking,
      ));

      if (result.points.isNotEmpty) {
        routeCoords
            .addAll(result.points.map((p) => LatLng(p.latitude, p.longitude)));
      }
    }

    return routeCoords;
  }
}
