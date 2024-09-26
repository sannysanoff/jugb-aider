import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'dart:typed_data';
import 'package:vector_math/vector_math_64.dart' show Vector3;
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'dart:async';
import 'dart:collection';
import 'dart:ui' as ui;
import 'pixel_painter_canvas.dart';

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
    _pixels = Uint8List(_canvasWidth * _canvasHeight * 4);
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
    try {
      // Ensure pixel data is valid and convert to RGBA if necessary
      Uint8List rgbaPixels;
      if (_pixels.length == _canvasWidth * _canvasHeight) {
        // Convert from grayscale to RGBA
        rgbaPixels = Uint8List(_canvasWidth * _canvasHeight * 4);
        for (int i = 0; i < _pixels.length; i++) {
          int j = i * 4;
          rgbaPixels[j] = _pixels[i];     // R
          rgbaPixels[j + 1] = _pixels[i]; // G
          rgbaPixels[j + 2] = _pixels[i]; // B
          rgbaPixels[j + 3] = 255;        // A (fully opaque)
        }
      } else if (_pixels.length == _canvasWidth * _canvasHeight * 4) {
        rgbaPixels = _pixels;
      } else {
        throw Exception('Invalid pixel data length');
      }

      final completer = Completer<ui.Image>();
      ui.decodeImageFromPixels(
        rgbaPixels,
        _canvasWidth,
        _canvasHeight,
        ui.PixelFormat.rgba8888,
        completer.complete,
      );
      
      _cachedImage = await completer.future;
      _needsImageUpdate = false;
      setState(() {});
    } catch (e) {
      _cachedImage = null;
      _needsImageUpdate = true;
      // Add a delay before retrying
      await Future.delayed(Duration(seconds: 1));
      if (mounted) {
        setState(() {}); // Trigger a rebuild to retry
      }
    }
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
        _reschedulePixelUpdate(pixelCoord);
      }
    } catch (e) {
      print('Error updating pixel: $e');
      _reschedulePixelUpdate(pixelCoord);
    } finally {
      _inFlightRequests--;
      _processPixelUpdateQueue(); // Try to process more pixels if possible
    }
  }

  void _reschedulePixelUpdate(String pixelCoord) {
    // Add the pixel back to the queue for retry
    if (!_pixelUpdateQueue.contains(pixelCoord)) {
      _pixelUpdateQueue.addLast(pixelCoord);
    }
  }

  void _connectWebSocket() {
    _channel = WebSocketChannel.connect(Uri.parse('wss://b.jugregator.org/ws'));
    _channel.stream.listen((message) {
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
    _needsImageUpdate = true;
    setState(() {});
  }

  void _updatePixels(List<dynamic> coordinates, bool isOn) {
    for (final coord in coordinates) {
      final String coordStr = coord.toString().padLeft(6, '0');
      final int y = int.parse(coordStr.substring(0, 3));
      final int x = int.parse(coordStr.substring(3));
      if (x >= 0 && x < _canvasWidth && y >= 0 && y < _canvasHeight) {
        int index = (y * _canvasWidth + x) * 4;
        int color = isOn ? 0 : 255;
        _pixels[index] = color;     // Red
        _pixels[index + 1] = color; // Green
        _pixels[index + 2] = color; // Blue
        _pixels[index + 3] = 255;   // Alpha (fully opaque)
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
            int pixelIndex = (i * 8 + bit) * 4;
            if (pixelIndex < _pixels.length) {
              int color = ((decodedBytes[i] >> bit) & 1) == 1 ? 0 : 255;
              _pixels[pixelIndex] = color;     // R
              _pixels[pixelIndex + 1] = color; // G
              _pixels[pixelIndex + 2] = color; // B
              _pixels[pixelIndex + 3] = 255;   // A (fully opaque)
            }
          }
        }
      } else {
        _initializeWhiteCanvas();
      }
    } catch (e) {
      _initializeWhiteCanvas();
    }
    _needsImageUpdate = true;
    setState(() {});
  }

  void _initializeWhiteCanvas() {
    for (int i = 0; i < _pixels.length; i += 4) {
      _pixels[i] = 255;     // R
      _pixels[i + 1] = 255; // G
      _pixels[i + 2] = 255; // B
      _pixels[i + 3] = 255; // A
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerSignal: (pointerSignal) {
        if (pointerSignal is PointerScrollEvent) {
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
          painter: PixelPainterCanvas(_pixels, _canvasWidth, _transform, _cachedImage),
        ),
      ),
    );
  }

  void invertPixel(int x, int y) {
    if (x >= 0 && x < _canvasWidth && y >= 0 && y < _canvasHeight) {
      int index = (y * _canvasWidth + x) * 4;
      _pixels[index] = 255;    // Red (full intensity)
      _pixels[index + 1] = 0;  // Green
      _pixels[index + 2] = 0;  // Blue
      _pixels[index + 3] = 255; // Alpha (fully opaque)
      
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
