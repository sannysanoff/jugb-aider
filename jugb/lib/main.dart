import 'package:flutter/material.dart';
import 'dart:typed_data';

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
  Offset? _lastPosition;
  double _scale = 1.0;
  Offset _offset = Offset.zero;
  final int _canvasWidth = 1000;
  final int _canvasHeight = 1000;
  late Uint8List _pixels;

  @override
  void initState() {
    super.initState();
    _pixels = Uint8List(_canvasWidth * _canvasHeight); // Initialize pixel data
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GestureDetector(
        onScaleStart: (details) {
          _lastPosition = details.localFocalPoint;
        },
        onScaleUpdate: (details) {
          if (_lastPosition != null) {
            setState(() {
              _offset += details.localFocalPoint - _lastPosition!;
              _scale *= details.scale;
              _lastPosition = details.localFocalPoint;
            });
          }
        },
        onTapDown: (details) {
          _drawPixel(details.localPosition);
        },
        child: Transform(
          transform: Matrix4.identity()
            ..translate(_offset.dx, _offset.dy)
            ..scale(_scale),
          child: CustomPaint(
            size: Size(_canvasWidth.toDouble(), _canvasHeight.toDouble()), // Fixed size
            painter: _PixelPainter(_pixels, _canvasWidth, _scale), // Access _pixels after initialization
          ),
        ),
      ),
    );
  }

  void _drawPixel(Offset position) {
    final x = (position.dx / _scale - _offset.dx / _scale).round();
    final y = (position.dy / _scale - _offset.dy / _scale).round();

    if (x >= 0 && x < _canvasWidth && y >= 0 && y < _canvasHeight) {
      setState(() {
        _pixels[y * _canvasWidth + x] = 1; // Set pixel to "on" (1)
      });
    }
  }
}


class _PixelPainter extends CustomPainter {
  final Uint8List pixels;
  final int canvasWidth;
  final double scale;

  _PixelPainter(this.pixels, this.canvasWidth, this.scale);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black
      ..strokeWidth = 1.0 / scale;

    for (int y = 0; y < size.height.toInt(); y++) {
      for (int x = 0; x < canvasWidth; x++) {
        if (pixels[y * canvasWidth + x] == 1) { // Check if pixel is "on"
          canvas.drawCircle(Offset(x.toDouble(), y.toDouble()), 0.5 / scale, paint); // Draw a small circle for each pixel
        }
      }
    }


    // Draw grid lines (when zoomed in)
    if (scale > 1.0) {
      final gridPaint = Paint()
        ..color = Colors.grey
        ..strokeWidth = 0.5 / scale;

      for (double x = 0; x < size.width; x += 1.0) {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
      }
      for (double y = 0; y < size.height; y += 1.0) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true; // Always repaint for now.  Consider optimizing this later.
  }
}
