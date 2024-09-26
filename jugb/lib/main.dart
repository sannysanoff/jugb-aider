import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:typed_data';
import 'package:vector_math/vector_math_64.dart' show Vector3;
import 'package:http/http.dart' as http;
import 'dart:convert';

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
  late Uint8List _pixels;
  Matrix4 _transform = Matrix4.identity();
  Offset? _lastPanPosition;
  Offset? _lastDrawPosition;

  @override
  void initState() {
    super.initState();
    _pixels = Uint8List(1000 * 1000);
    _fetchInitialState();
  }

  Future<void> _fetchInitialState() async {
    final response = await http.get(Uri.parse('https://b.jugregator.org/api/grid'));
    if (response.statusCode == 200) {
      final decodedBytes = base64.decode(response.body);
      for (int i = 0; i < decodedBytes.length; i++) {
        for (int bit = 0; bit < 8; bit++) {
          int pixelIndex = i * 8 + bit;
          if (pixelIndex < _pixels.length) {
            _pixels[pixelIndex] = ((decodedBytes[i] >> bit) & 1) == 1 ? 0 : 255;
          }
        }
      }
      setState(() {});
    } else {
      print('Failed to load initial state');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Listener(
        onPointerSignal: (pointerSignal) {
          if (pointerSignal is PointerScrollEvent) {
            print('Mouse wheel event detected:');
            print('  Scroll delta: ${pointerSignal.scrollDelta}');
            print('  Local position: ${pointerSignal.localPosition}');
            
            setState(() {
              // Determine zoom factor based on scroll direction
              double zoomFactor = 1 - (pointerSignal.scrollDelta.dy / 500);
              
              // Prevent zooming out beyond 1:1
              if (_transform.getMaxScaleOnAxis() * zoomFactor < 1) {
                zoomFactor = 1 / _transform.getMaxScaleOnAxis();
              }
              
              // Calculate the focal point in the canvas coordinate system
              final focalPointInCanvas = _transform.clone()..invert();
              final transformedPoint = focalPointInCanvas.transform3(Vector3(
                pointerSignal.localPosition.dx,
                pointerSignal.localPosition.dy,
                0,
              ));

              // Apply zooming
              _transform = Matrix4.identity()
                ..translate(pointerSignal.localPosition.dx, pointerSignal.localPosition.dy)
                ..scale(zoomFactor)
                ..translate(-pointerSignal.localPosition.dx, -pointerSignal.localPosition.dy)
                ..multiply(_transform);
            });
          }
        },
        child: Listener(
          onPointerDown: (PointerDownEvent event) {
            if (event.kind == PointerDeviceKind.mouse) {
              if (event.buttons == kMiddleMouseButton) {
                _lastPanPosition = event.localPosition;
              } else if (event.buttons == kPrimaryMouseButton) {
                // Handle single click for left mouse button
                final inverseTransform = Matrix4.inverted(_transform);
                final transformedPoint = inverseTransform.transform3(Vector3(
                  event.localPosition.dx,
                  event.localPosition.dy,
                  0,
                ));
                final x = transformedPoint.x.round();
                final y = transformedPoint.y.round();
                invertPixel(x, y);
                _lastDrawPosition = Offset(x.toDouble(), y.toDouble());
              }
            }
          },
          onPointerMove: (PointerMoveEvent event) {
            if (event.kind == PointerDeviceKind.mouse) {
              if (event.buttons == kMiddleMouseButton) {
                // Middle mouse button: pan
                setState(() {
                  final dx = event.localPosition.dx - _lastPanPosition!.dx;
                  final dy = event.localPosition.dy - _lastPanPosition!.dy;
                  _transform = Matrix4.identity()
                    ..translate(dx, dy)
                    ..multiply(_transform);
                  _lastPanPosition = event.localPosition;
                });
              } else if (event.buttons == kPrimaryMouseButton) {
                // Left mouse button: draw (continuous)
                final inverseTransform = Matrix4.inverted(_transform);
                final transformedPoint = inverseTransform.transform3(Vector3(
                  event.localPosition.dx,
                  event.localPosition.dy,
                  0,
                ));
                final x = transformedPoint.x.round();
                final y = transformedPoint.y.round();
                
                // Only invert pixel if we've moved to a new square
                if (_lastDrawPosition == null || 
                    x != _lastDrawPosition!.dx.round() || 
                    y != _lastDrawPosition!.dy.round()) {
                  invertPixel(x, y);
                  _lastDrawPosition = Offset(x.toDouble(), y.toDouble());
                }
              }
            }
          },
          onPointerUp: (PointerUpEvent event) {
            if (event.kind == PointerDeviceKind.mouse) {
              _lastDrawPosition = null;
            }
          },
        child: CustomPaint(
          size: Size(_canvasWidth.toDouble(), _canvasHeight.toDouble()),
          painter: _PixelPainter(_pixels, _canvasWidth, _transform),
        ),
      ),
    ));
  }

  void invertPixel(int x, int y) {
    if (x >= 0 && x < _canvasWidth && y >= 0 && y < _canvasHeight) {
      int index = y * _canvasWidth + x;
      _pixels[index] = 255 - _pixels[index];  // Invert the color
      setState(() {});
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
        final color = Color.fromRGBO(
          pixels[y * canvasWidth + x],
          pixels[y * canvasWidth + x],
          pixels[y * canvasWidth + x],
          1
        );
        final rect = Rect.fromLTWH(x.toDouble(), y.toDouble(), 1.0, 1.0);
        canvas.drawRect(rect, Paint()..color = color);
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
