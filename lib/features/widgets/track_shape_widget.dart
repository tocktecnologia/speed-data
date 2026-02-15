
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'dart:math';
import 'dart:ui' as ui;

class TrackPainter extends CustomPainter {
  final List<LatLng> checkpoints;
  final List<LatLng> routePath;

  TrackPainter({required this.checkpoints, required this.routePath});

  @override
  void paint(Canvas canvas, Size size) {
    if (checkpoints.isEmpty && routePath.isEmpty) return;

    final paint = Paint()
      ..color = Colors.blue
      ..strokeWidth = 4.0
      ..style = PaintingStyle.stroke;

    final pointPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 6.0
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke; // Draw as points

    // 1. Calculate bounding box
    double minLat = double.infinity;
    double maxLat = -double.infinity;
    double minLng = double.infinity;
    double maxLng = -double.infinity;

    final allPoints = [...routePath, ...checkpoints];
    for (var p in allPoints) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }

    // Add padding to bounding box
    const padding = 20.0;
    final latRange = maxLat - minLat;
    final lngRange = maxLng - minLng;

    if (latRange == 0 || lngRange == 0) return;

    // 2. Scale transform
    // Mercator projection approximation for small areas (simple linear scaling)
    // Invert Y because screen Y goes down, Latitude Y goes up
    
    // Determine scale factor to fit within size - 2*padding
    final availableWidth = size.width - 2 * padding;
    final availableHeight = size.height - 2 * padding;

    final scaleX = availableWidth / lngRange;
    final scaleY = availableHeight / latRange;
    
    // Use the smaller scale to maintain aspect ratio
    final scale = min(scaleX, scaleY);
    
    // Center the track
    final plotWidth = lngRange * scale;
    final plotHeight = latRange * scale;
    final startX = padding + (availableWidth - plotWidth) / 2;
    final startY = padding + (availableHeight - plotHeight) / 2;

    Offset toScreen(LatLng latLng) {
       final x = (latLng.longitude - minLng) * scale + startX;
       final y = (maxLat - latLng.latitude) * scale + startY; // Invert Y
       return Offset(x, y);
    }

    // 3. Draw Route Path
    if (routePath.isNotEmpty) {
      final path = Path();
      path.moveTo(toScreen(routePath[0]).dx, toScreen(routePath[0]).dy);
      for (var i = 1; i < routePath.length; i++) {
        path.lineTo(toScreen(routePath[i]).dx, toScreen(routePath[i]).dy);
      }
      // If loop? Usually race tracks loop. Route path might not be closed in data.
      // We assume routePath draws the line.
      canvas.drawPath(path, paint);
    } else {
       // Fallback to checkpoints if no route
       if (checkpoints.isNotEmpty) {
         final path = Path();
          path.moveTo(toScreen(checkpoints[0]).dx, toScreen(checkpoints[0]).dy);
          for (var i = 1; i < checkpoints.length; i++) {
            path.lineTo(toScreen(checkpoints[i]).dx, toScreen(checkpoints[i]).dy);
          }
          path.close(); // Assume closed loop for checkpoints-only
          canvas.drawPath(path, paint);
       }
    }

    // 4. Draw Checkpoints
    for (var p in checkpoints) {
       canvas.drawPoints(ui.PointMode.points, [toScreen(p)], pointPaint);
    }
    
    // Start/Finish Line (First checkpoint)
    if (checkpoints.isNotEmpty) {
       final start = toScreen(checkpoints.first);
       final sfPaint = Paint()
         ..color = Colors.green
         ..strokeWidth = 6.0;
       canvas.drawCircle(start, 4.0, sfPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// Need to import dart:ui as ui
