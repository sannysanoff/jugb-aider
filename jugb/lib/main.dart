import 'package:flutter/gestures.dart'; // Import for PointerScrollEvent
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
  Uint8List _pixels = Uint8List(1000 * 1000); // Initialize _pixels here

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Listener(
        onPointerSignal: (pointerSignal) {
          if (pointerSignal is PointerScrollEvent) {
            setState(() {
              double zoomFactor = 0.1;
              _scale += pointerSignal.scrollDelta.dy * zoomFactor * -1; // Zoom in/out
              _scale = _scale.clamp(0.1, 10.0); // Limit zoom level

              // Adjust offset based on zoom origin
              Offset focalPoint = pointerSignal.localPosition;
              _offset = (focalPoint - (focalPoint - _offset) / _scale * _scale);
            });
          }
        },
        child: GestureDetector(
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
            togglePixel(details.localPosition);
          },
          child: Transform(
            transform: Matrix4.identity()
              ..translate(_offset.dx, _offset.dy)
              ..scale(_scale),
            child: CustomPaint(
              size: Size(_canvasWidth.toDouble(), _canvasHeight.toDouble()), // Fixed size
              painter: _PixelPainter(_pixels, _canvasWidth, _scale, _offset),
            ),
          ),
        ),
      ),
    );
  }

  void togglePixel(Offset position) {
    // Apply inverse transformation to get correct pixel coordinates
    final x = ((position.dx - _offset.dx) / _scale).round();
    final y = ((position.dy - _offset.dy) / _scale).round();

    // Check if the click is within the bounds of the canvas
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
  final Offset offset;

  _PixelPainter(this.pixels, this.canvasWidth, this.scale, this.offset);

  @override
  void paint(Canvas canvas, Size size) {
    // Apply the transformations to the canvas
    canvas.translate(offset.dx, offset.dy);
    canvas.scale(scale);

    for (int y = 0; y < size.height.toInt(); y++) {
      for (int x = 0; x < canvasWidth; x++) {
        if (pixels[y * canvasWidth + x] == 1) { // Check if pixel is "on"
          // Fill grid square
          final rect = Rect.fromLTWH(x.toDouble(), y.toDouble(), 1.0, 1.0);
          canvas.drawRect(rect, Paint()..color = Colors.black);
        }
      }
    }


    // Draw grid lines (when zoomed in) - adjust for scale
    if (scale > 1.0) {
      final gridPaint = Paint()
        ..color = Colors.grey
        ..strokeWidth = 0.5 / scale; // Adjust stroke width based on scale

      for (double x = 0; x <= size.width; x += 1.0) {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
      }
      for (double y = 0; y <= size.height; y += 1.0) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true; // Always repaint for now.  Consider optimizing this later.
  }
}
