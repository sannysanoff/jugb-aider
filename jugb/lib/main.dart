import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:typed_data';
import 'package:vector_math/vector_math_64.dart' show Vector3;
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'dart:async';
import 'dart:collection';
import 'dart:ui' as ui;

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

import 'dart:ui' as ui;

class _PixelPainterState extends State<PixelPainter> {
  final int _canvasWidth = 1000;
  final int _canvasHeight = 1000;
  late Uint8List _pixels;
  Matrix4 _transform = Matrix4.identity();
  Offset? _lastPanPosition;
  Offset? _lastDrawPosition;
  late WebSocketChannel _channel;
  final _pixelUpdateQueue = Queue<String>();
  Timer? _updateTimer;
  int _inFlightRequests = 0;
  static const int _maxConcurrentRequests = 4;
  ui.Image? _cachedImage;
  bool _needsImageUpdate = true;

  @override
  void initState() {
    super.initState();
    _pixels = Uint8List(1000 * 1000);
    _fetchInitialState();
    _connectWebSocket();
    _startUpdateTimer();
    _startImageUpdateTimer();
  }

  void _startImageUpdateTimer() {
    Timer.periodic(Duration(milliseconds: 100), (_) {
      if (_needsImageUpdate) {
        _updateCachedImage();
      }
    });
  }

  Future<void> _updateCachedImage() async {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      _pixels,
      _canvasWidth,
      _canvasHeight,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    _cachedImage = await completer.future;
    _needsImageUpdate = false;
    setState(() {});
  }

  void _startUpdateTimer() {
    _updateTimer = Timer.periodic(Duration(milliseconds: 200), (_) {
      _processPixelUpdateQueue();
    });
  }

  void _processPixelUpdateQueue() {
    while (_inFlightRequests < _maxConcurrentRequests && _pixelUpdateQueue.isNotEmpty) {
      final pixelToUpdate = _pixelUpdateQueue.removeFirst();
      _sendPixelUpdate(pixelToUpdate);
    }
  }

  void _sendPixelUpdate(String pixelCoord) async {
    _inFlightRequests++;
    final url = Uri.parse('https://b.jugregator.org/set/$pixelCoord');
    try {
      final response = await http.post(url);
      if (response.statusCode != 200) {
        print('Failed to update pixel: ${response.statusCode}');
        // Optionally, you can add the pixel back to the queue for retry
        // _pixelUpdateQueue.addLast(pixelCoord);
      }
    } catch (e) {
      print('Error updating pixel: $e');
      // Optionally, you can add the pixel back to the queue for retry
      // _pixelUpdateQueue.addLast(pixelCoord);
    } finally {
      _inFlightRequests--;
      _processPixelUpdateQueue(); // Try to process more pixels if possible
    }
  }

  void _connectWebSocket() {
    _channel = WebSocketChannel.connect(Uri.parse('wss://b.jugregator.org/ws'));
    _channel.stream.listen((message) {
      print('Received WebSocket message: $message');
      final data = jsonDecode(message);
      _handleWebSocketMessage(data);
    });
  }

  void _handleWebSocketMessage(Map<String, dynamic> data) {
    if (data.containsKey('on')) {
      _updatePixels(data['on'] as List<dynamic>, true);
    }
    if (data.containsKey('off')) {
      _updatePixels(data['off'] as List<dynamic>, false);
    }
    setState(() {});
  }

  void _updatePixels(List<dynamic> coordinates, bool isOn) {
    for (final coord in coordinates) {
      final String coordStr = coord.toString().padLeft(6, '0');
      final int y = int.parse(coordStr.substring(0, 3));
      final int x = int.parse(coordStr.substring(3));
      if (x >= 0 && x < _canvasWidth && y >= 0 && y < _canvasHeight) {
        int index = y * _canvasWidth + x;
        _pixels[index] = isOn ? 0 : 255;
      }
    }
  }

  @override
  void dispose() {
    _channel.sink.close();
    _updateTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchInitialState() async {
    try {
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
      } else {
        print('Failed to load initial state: ${response.statusCode}');
        _initializeWhiteCanvas();
      }
    } catch (e) {
      print('Error fetching initial state: $e');
      _initializeWhiteCanvas();
    }
    setState(() {});
  }

  void _initializeWhiteCanvas() {
    _pixels.fillRange(0, _pixels.length, 255);
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
          painter: _PixelPainter(_pixels, _canvasWidth, _transform, _cachedImage),
        ),
      ),
    ));
  }

  void invertPixel(int x, int y) {
    if (x >= 0 && x < _canvasWidth && y >= 0 && y < _canvasHeight) {
      int index = y * _canvasWidth + x;
      _pixels[index] = 80;  // Set to 80 (will be drawn as red)
      _needsImageUpdate = true;
      setState(() {});
      
      // Add to update queue
      String pixelCoord = '${y.toString().padLeft(3, '0')}${x.toString().padLeft(3, '0')}';
      if (!_pixelUpdateQueue.contains(pixelCoord)) {
        _pixelUpdateQueue.addLast(pixelCoord);
        _processPixelUpdateQueue(); // Try to process immediately if possible
      }
    }
  }
}

class _PixelPainter extends CustomPainter {
  final Uint8List pixels;
  final int canvasWidth;
  final Matrix4 transform;
  final ui.Image? cachedImage;

  _PixelPainter(this.pixels, this.canvasWidth, this.transform, this.cachedImage);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.transform(transform.storage);

    if (cachedImage != null) {
      canvas.drawImage(cachedImage!, Offset.zero, Paint());
    } else {
      // Fallback to pixel-by-pixel drawing if image is not available
      for (int y = 0; y < size.height.toInt(); y++) {
        for (int x = 0; x < canvasWidth; x++) {
          final pixelValue = pixels[y * canvasWidth + x];
          final color = pixelValue == 80 ? Colors.red : Color.fromRGBO(
            pixelValue,
            pixelValue,
            pixelValue,
            1
          );
          final rect = Rect.fromLTWH(x.toDouble(), y.toDouble(), 1.0, 1.0);
          canvas.drawRect(rect, Paint()..color = color);
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
  bool shouldRepaint(covariant _PixelPainter oldDelegate) {
    return pixels != oldDelegate.pixels || transform != oldDelegate.transform || cachedImage != oldDelegate.cachedImage;
  }
}
