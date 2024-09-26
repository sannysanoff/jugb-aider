import 'package:flutter/material.dart';
import 'dart:typed_data';
import 'dart:ui' as ui;

class PixelPainterCanvas extends CustomPainter {
  final Uint8List pixels;
  final int canvasWidth;
  final Matrix4 transform;
  final ui.Image? cachedImage;

  PixelPainterCanvas(this.pixels, this.canvasWidth, this.transform, this.cachedImage);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.transform(transform.storage);

    if (cachedImage != null) {
      canvas.drawImage(cachedImage!, Offset.zero, Paint());
    } else {
      // Fallback to pixel-by-pixel drawing if image is not available
      final int maxY = size.height.toInt().clamp(0, pixels.length ~/ (canvasWidth * 4) - 1);
      final int maxX = canvasWidth.clamp(0, pixels.length ~/ 4 - 1);
      for (int y = 0; y < maxY; y++) {
        for (int x = 0; x < maxX; x++) {
          final index = (y *canvasWidth + x) * 4;
          if (index + 3 < pixels.length) {
            final color = Color.fromARGB(
              pixels[index + 3],
              pixels[index],
              pixels[index + 1],
              pixels[index + 2],
            );
            final rect = Rect.fromLTWH(x.toDouble(), y.toDouble(), 1.0, 1.0);
            canvas.drawRect(rect, Paint()..color = color);
          }
        }
      }
    }

    // Draw grid lines only if zoom level is 10 or greater
    if (transform.getMaxScaleOnAxis() >= 10) {
      final gridPaint = Paint()
        ..color = Colors.grey
        ..strokeWidth = 0.1;

      for (double x = 0; x <= size.width; x += 1.0) {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
      }
      for (double y = 0; y <= size.height; y += 1.0) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant PixelPainterCanvas oldDelegate) {
    return pixels != oldDelegate.pixels || transform != oldDelegate.transform || cachedImage != oldDelegate.cachedImage;
  }
}
