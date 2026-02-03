import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'dart:typed_data';

class MarkerGenerator {
  static Future<BitmapDescriptor> createCustomMarkerBitmap(
    String name,
    String speed,
  ) async {
    final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(pictureRecorder);

    // Config
    const double fontSize = 28.0;
    const double padding = 16.0;
    const double pinHeadRadius = 24.0;
    const double pinTipHeight = 24.0;
    const double gap = 12.0;

    // Colors
    // Azure approx HSV(210, 1.0, 1.0)
    final Color pinColor = HSVColor.fromAHSV(1.0, 210.0, 1.0, 1.0).toColor();
    final Color textColor = Colors.black87;
    final Color boxColor = Colors.white;
    final Color boxBorderColor = Colors.grey.shade300;

    // Text Setup
    final String text = "$name\n$speed";
    final TextSpan textSpan = TextSpan(
      text: text,
      style: TextStyle(
        fontSize: fontSize,
        color: textColor,
        fontWeight: FontWeight.bold,
        fontFamily: 'Roboto',
      ),
    );
    final TextPainter textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );
    textPainter.layout();

    final double textWidth = textPainter.width;
    final double textHeight = textPainter.height;

    // Dimensions
    final double boxWidth = textWidth + padding * 2;
    final double boxHeight = textHeight + padding * 2;

    final double pinTotalHeight = pinHeadRadius * 2 + pinTipHeight;
    final double totalW =
        (boxWidth > pinHeadRadius * 2) ? boxWidth : pinHeadRadius * 2;
    // Ensure we have some safe margin
    final double canvasWidth = totalW + 20;
    final double centerX = canvasWidth / 2;

    final double totalH = boxHeight + gap + pinTotalHeight + 10; // +10 buffer

    // Position Label at top
    final double labelTop = 5.0;
    final RRect labelRect = RRect.fromLTRBR(
      centerX - boxWidth / 2,
      labelTop,
      centerX + boxWidth / 2,
      labelTop + boxHeight,
      Radius.circular(12),
    );

    // Draw Label Box Shadow
    final Paint shadowPaint = Paint()
      ..color = Colors.black26
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

    final RRect shadowRect = labelRect.shift(const Offset(0, 2));
    canvas.drawRRect(shadowRect, shadowPaint);

    // Draw Label Box
    final Paint boxPaint = Paint()
      ..color = boxColor
      ..style = PaintingStyle.fill;

    canvas.drawRRect(labelRect, boxPaint);

    // Border for label
    final Paint borderPaint = Paint()
      ..color = boxBorderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    canvas.drawRRect(labelRect, borderPaint);

    // Draw Text
    textPainter.paint(
        canvas, Offset(centerX - textWidth / 2, labelTop + padding));

    // Draw Pin
    final double pinStartY = labelTop + boxHeight + gap;

    final centerParams = Offset(centerX, pinStartY + pinHeadRadius);

    final Paint pinPaint = Paint()..color = pinColor;

    // Draw Pin Shape
    Path p = Path();
    // Start at bottom tip
    final Offset tip = Offset(centerX, pinStartY + pinTotalHeight);

    p.moveTo(tip.dx, tip.dy);
    // Curve up to left
    p.quadraticBezierTo(
      centerX - pinHeadRadius, pinStartY + pinHeadRadius * 2, // control point
      centerX - pinHeadRadius,
      pinStartY + pinHeadRadius, // end point (left tangent)
    );
    // Arc around top
    p.arcToPoint(
      Offset(centerX + pinHeadRadius, pinStartY + pinHeadRadius),
      radius: Radius.circular(pinHeadRadius),
      largeArc: true,
    );
    // Curve down to tip
    p.quadraticBezierTo(
      centerX + pinHeadRadius,
      pinStartY + pinHeadRadius * 2,
      tip.dx,
      tip.dy,
    );
    p.close();

    // Shadow for Pin
    canvas.drawPath(
        p.shift(Offset(0, 3)),
        Paint()
          ..color = Colors.black26
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 5));

    canvas.drawPath(p, pinPaint);

    // Inner dot (Standard Google marker has a darker dot)
    final Paint dotPaint = Paint()..color = Colors.black.withOpacity(0.25);
    canvas.drawCircle(centerParams, pinHeadRadius * 0.35, dotPaint);

    // Convert to Image
    final ui.Image image = await pictureRecorder.endRecording().toImage(
          canvasWidth.toInt(),
          totalH.toInt(),
        );

    final ByteData? byteData =
        await image.toByteData(format: ui.ImageByteFormat.png);
    final Uint8List uint8List = byteData!.buffer.asUint8List();

    return BitmapDescriptor.fromBytes(uint8List);
  }
}
