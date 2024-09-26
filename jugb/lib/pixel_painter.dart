import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;
import 'dart:ui' as ui;
import 'pixel_painter_canvas.dart';
import 'pixel_data_manager.dart';

class PixelPainter extends StatefulWidget {
  const PixelPainter({super.key});

  @override
  State<PixelPainter> createState() => _PixelPainterState();
}

class _PixelPainterState extends State<PixelPainter> {
  final int _canvasWidth = 1000;
  final int _canvasHeight = 1000;
  late PixelDataManager _pixelDataManager;
  Matrix4 _transform = Matrix4.identity();
  Offset? _lastPanPosition;
  Offset? _lastDrawPosition;
  ui.Image? _cachedImage;
  bool _needsImageUpdate = true;

  @override
  void initState() {
    super.initState();
    _pixelDataManager = PixelDataManager(canvasWidth: _canvasWidth, canvasHeight: _canvasHeight);
    _pixelDataManager.pixelsChanged.listen((_) {
      _needsImageUpdate = true;
      setState(() {});
    });
    _startImageUpdateTimer();
  }

  void _startImageUpdateTimer() {
    Future.doWhile(() async {
      await Future.delayed(Duration(milliseconds: 100));
      if (_needsImageUpdate) {
        await _updateCachedImage();
      }
      return true; // Continue the loop
    });
  }

  Future<void> _updateCachedImage() async {
    try {
      final completer = Completer<ui.Image>();
      ui.decodeImageFromPixels(
        _pixelDataManager.pixels,
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

  @override
  void dispose() {
    _pixelDataManager.dispose();
    super.dispose();
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
              _pixelDataManager.invertPixel(x, y);
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
                _pixelDataManager.invertPixel(x, y);
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
          painter: PixelPainterCanvas(_pixelDataManager.pixels, _canvasWidth, _transform, _cachedImage),
        ),
      ),
    );
  }
}
