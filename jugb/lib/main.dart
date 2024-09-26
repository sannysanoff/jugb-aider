import 'package:flutter/material.dart';

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
        child: Transform(
          transform: Matrix4.identity()
            ..translate(_offset.dx, _offset.dy)
            ..scale(_scale),
          child: CustomPaint(
            size: Size.infinite,
            painter: _PixelPainter(),
          ),
        ),
      ),
    );
  }
}

class _PixelPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black
      ..strokeWidth = 1.0 / _PixelPainterState()._scale; // Scale stroke width

    // Example: Draw a pixel where the user clicks
    if (_PixelPainterState()._lastPosition != null) {
      canvas.drawCircle(_PixelPainterState()._lastPosition!, 5.0 / _PixelPainterState()._scale, paint);
    }

    // Draw grid lines (when zoomed in)
    if (_PixelPainterState()._scale > 1.0) {
      final gridPaint = Paint()
        ..color = Colors.grey
        ..strokeWidth = 0.5 / _PixelPainterState()._scale;

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
    return true;
  }
}
