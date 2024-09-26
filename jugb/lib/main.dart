import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'dart:typed_data';
import 'dart:math' show Point;

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pixel Painter',
      home: const PixelPainter(),
    );
  }
}

class PixelPainter extends StatefulWidget {
  const PixelPainter({super.key});

  @override
  State<PixelPainter> createState() => _PixelPainterState();
}

class _PixelPainterState extends State<PixelPainter> {
  final int _canvasWidth = 1000;
  final int _canvasHeight = 1000;
  Uint8List _pixels = Uint8List(1000 * 1000);
  Matrix4 _transform = Matrix4.identity();
  Point<double>? _lastPanPosition;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GestureDetector(
        onPanStart: (details) {
          _lastPanPosition = Point(details.localPosition.dx, details.localPosition.dy);
        },
        onPanUpdate: (details) {
          if (_lastPanPosition != null) {
            final dx = details.localPosition.dx - _lastPanPosition!.x;
            final dy = details.localPosition.dy - _lastPanPosition!.y;
            setState(() {
              _transform = Matrix4.identity()
                ..multiply(_transform)
                ..translate(dx, dy);
            });
            _lastPanPosition = Point(details.localPosition.dx, details.localPosition.dy);
          }
        },
        onScaleUpdate: (details) {
          setState(() {
            final scaleDiff = details.scale;
            final focalPoint = details.localFocalPoint;
            _transform = Matrix4.identity()
              ..translate(focalPoint.dx, focalPoint.dy)
              ..scale(scaleDiff)
              ..translate(-focalPoint.dx, -focalPoint.dy)
              ..multiply(_transform);
          });
        },
        onTapDown: (details) {
          final inverseTransform = Matrix4.inverted(_transform);
          final transformedPoint = inverseTransform.transform3(Vector3(
            details.localPosition.dx,
            details.localPosition.dy,
            0,
          ));
          final x = transformedPoint.x.round();
          final y = transformedPoint.y.round();
          togglePixel(x, y);
        },
        child: CustomPaint(
          size: Size(_canvasWidth.toDouble(), _canvasHeight.toDouble()),
          painter: _PixelPainter(_pixels, _canvasWidth, _transform),
        ),
      ),
    );
  }

  void togglePixel(int x, int y) {
    if (x >= 0 && x < _canvasWidth && y >= 0 && y < _canvasHeight) {
      setState(() {
        int index = y * _canvasWidth + x;
        _pixels[index] = (_pixels[index] == 0) ? 1 : 0;
      });
    }
  }
}

class _PixelPainter extends CustomPainter {
  final Uint8List pixels;
  final int canvasWidth;
  final Matrix4 transform;

  _PixelPainter(this.pixels, this.canvasWidth, this.transform);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.transform(transform.storage);

    for (int y = 0; y < size.height.toInt(); y++) {
      for (int x = 0; x < canvasWidth; x++) {
        if (pixels[y * canvasWidth + x] == 1) {
          final rect = Rect.fromLTWH(x.toDouble(), y.toDouble(), 1.0, 1.0);
          canvas.drawRect(rect, Paint()..color = Colors.black);
        }
      }
    }

    // Draw grid lines
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

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}
