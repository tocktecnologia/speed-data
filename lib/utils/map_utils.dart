import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

Future<BitmapDescriptor> createCustomMarkerBitmap(String label,
    {Color color = Colors.red}) async {
  final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
  final Canvas canvas = Canvas(pictureRecorder);

  // Canvas size
  const double width = 60;
  const double height = 85;

  final Paint paint = Paint()..color = color;
  final Paint borderPaint = Paint()
    ..color = Colors.white
    ..strokeWidth = 4
    ..style = PaintingStyle.stroke;

  // Pin Geometry
  final double radius = 32.0;
  final double cx = width / 2;
  final double cy = radius + 8; // move down a bit specifically

  final Path path = Path();
  path.moveTo(cx, height); // Tip at bottom center

  // Right curve to head
  path.quadraticBezierTo(width - 5, height * 0.6, width, cy);
  // Top arc (head)
  path.arcToPoint(Offset(0, cy),
      radius: Radius.circular(width / 2), largeArc: true, clockwise: false);
  // Left curve to tip
  path.quadraticBezierTo(5, height * 0.6, cx, height);

  path.close();

  // Draw shadow (optional, maybe complicated for raw canvas)

  // Draw filled pin
  canvas.drawPath(path, paint);
  // Draw border
  canvas.drawPath(path, borderPaint);

  // Text setup
  final TextPainter textPainter = TextPainter(
    textDirection: TextDirection.ltr,
  );
  textPainter.text = TextSpan(
    text: label,
    style: const TextStyle(
      fontSize: 35,
      color: Colors.white,
      fontWeight: FontWeight.bold,
    ),
  );

  textPainter.layout();
  textPainter.paint(
    canvas,
    Offset(
      cx - textPainter.width / 2,
      cy - textPainter.height / 2,
    ),
  );

  final ui.Image image = await pictureRecorder
      .endRecording()
      .toImage(width.toInt(), height.toInt());
  final ByteData? byteData =
      await image.toByteData(format: ui.ImageByteFormat.png);

  if (byteData == null) {
    return BitmapDescriptor.defaultMarker;
  }
  return BitmapDescriptor.fromBytes(byteData.buffer.asUint8List());
}
