import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'dart:math';
import 'dart:ui' as ui;

class PilotPosition {
  final String uid;
  final LatLng location;
  final Color color;
  final String label;

  const PilotPosition({
    required this.uid,
    required this.location,
    required this.color,
    required this.label,
  });
}

class TimelineOverlayPoint {
  final String id;
  final LatLng location;
  final String type; // start_finish | split | trap
  final String label; // SF, S1, T1...
  final int order;
  final bool enabled;
  final Color color;

  const TimelineOverlayPoint({
    required this.id,
    required this.location,
    required this.type,
    required this.label,
    required this.order,
    required this.enabled,
    required this.color,
  });
}

class TrackPainter extends CustomPainter {
  final List<LatLng> checkpoints;
  final List<LatLng> routePath;
  final List<PilotPosition> pilotPositions;
  final List<TimelineOverlayPoint> timelinePoints;

  TrackPainter({
    required this.checkpoints,
    required this.routePath,
    this.pilotPositions = const [],
    this.timelinePoints = const [],
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (checkpoints.isEmpty && routePath.isEmpty) return;

    final paint = Paint()
      ..color = Colors.blue.withOpacity(0.6)
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke;

    final pointPaint = Paint()
      ..color = Colors.white.withOpacity(0.35)
      ..strokeWidth = 4.0
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
        ..color = Colors.green.withOpacity(0.6)
        ..strokeWidth = 4.0;
      canvas.drawCircle(start, 3.0, sfPaint);
    }

    if (timelinePoints.isNotEmpty) {
      final ordered = List<TimelineOverlayPoint>.from(timelinePoints)
        ..sort((a, b) => a.order.compareTo(b.order));

      if (ordered.length > 1) {
        final orderPaint = Paint()
          ..color = Colors.white.withValues(alpha: 0.2)
          ..strokeWidth = 1.4
          ..style = PaintingStyle.stroke;
        final orderPath = Path();
        final start = toScreen(ordered.first.location);
        orderPath.moveTo(start.dx, start.dy);
        for (var i = 1; i < ordered.length; i++) {
          final p = toScreen(ordered[i].location);
          orderPath.lineTo(p.dx, p.dy);
        }
        canvas.drawPath(orderPath, orderPaint);
      }

      for (final timeline in ordered) {
        final point = toScreen(timeline.location);
        final color = timeline.enabled
            ? timeline.color.withValues(alpha: 0.95)
            : timeline.color.withValues(alpha: 0.45);
        final halo = Paint()
          ..color = color.withValues(alpha: timeline.enabled ? 0.25 : 0.12)
          ..style = PaintingStyle.fill;
        canvas.drawCircle(point, 10, halo);

        final markerPaint = Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2;
        if (timeline.type == 'start_finish') {
          final rect = Rect.fromCenter(center: point, width: 12, height: 12);
          canvas.drawRect(rect, markerPaint);
        } else if (timeline.type == 'trap') {
          final triangle = Path()
            ..moveTo(point.dx, point.dy - 7)
            ..lineTo(point.dx - 6.5, point.dy + 5)
            ..lineTo(point.dx + 6.5, point.dy + 5)
            ..close();
          canvas.drawPath(triangle, markerPaint);
        } else {
          canvas.drawCircle(point, 6, markerPaint);
        }

        final labelPainter = TextPainter(
          text: TextSpan(
            text: timeline.label,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w800,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        labelPainter.paint(canvas, point + const Offset(8, -12));
      }
    }

    if (pilotPositions.isNotEmpty) {
      final pilotPaint = Paint()..style = PaintingStyle.fill;
      for (var pilot in pilotPositions) {
        final point = toScreen(pilot.location);
        pilotPaint.color = pilot.color;
        canvas.drawCircle(point, 9.0, pilotPaint);
        final builder = TextPainter(
          text: TextSpan(
            text: pilot.label,
            style: TextStyle(
                color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        builder.paint(canvas, point + const Offset(8, -8));
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// Need to import dart:ui as ui
