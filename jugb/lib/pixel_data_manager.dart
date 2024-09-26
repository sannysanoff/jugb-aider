import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

class PixelDataManager {
  final int canvasWidth;
  final int canvasHeight;
  late Uint8List pixels;
  late WebSocketChannel _channel;
  final _pixelUpdateQueue = Queue<String>();
  Timer? _updateTimer;
  int _inFlightRequests = 0;
  static const int _maxConcurrentRequests = 4;

  final _pixelsChangedController = StreamController<void>.broadcast();
  Stream<void> get pixelsChanged => _pixelsChangedController.stream;

  PixelDataManager({required this.canvasWidth, required this.canvasHeight}) {
    pixels = Uint8List(canvasWidth * canvasHeight * 4);
    _fetchInitialState();
    _connectWebSocket();
    _startUpdateTimer();
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
    _pixelsChangedController.add(null);
  }

  void _updatePixels(List<dynamic> coordinates, bool isOn) {
    for (final coord in coordinates) {
      final String coordStr = coord.toString().padLeft(6, '0');
      final int y = int.parse(coordStr.substring(0, 3));
      final int x = int.parse(coordStr.substring(3));
      if (x >= 0 && x < canvasWidth && y >= 0 && y < canvasHeight) {
        int index = (y * canvasWidth + x) * 4;
        int color = isOn ? 0 : 255;
        pixels[index] = color;     // Red
        pixels[index + 1] = color; // Green
        pixels[index + 2] = color; // Blue
        pixels[index + 3] = 255;   // Alpha (fully opaque)
      }
    }
  }

  Future<void> _fetchInitialState() async {
    try {
      final response = await http.get(Uri.parse('https://b.jugregator.org/api/grid'));
      if (response.statusCode == 200) {
        final decodedBytes = base64.decode(response.body);
        for (int i = 0; i < decodedBytes.length; i++) {
          for (int bit = 0; bit < 8; bit++) {
            int pixelIndex = (i * 8 + bit) * 4;
            if (pixelIndex < pixels.length) {
              int color = ((decodedBytes[i] >> bit) & 1) == 1 ? 0 : 255;
              pixels[pixelIndex] = color;     // R
              pixels[pixelIndex + 1] = color; // G
              pixels[pixelIndex + 2] = color; // B
              pixels[pixelIndex + 3] = 255;   // A (fully opaque)
            }
          }
        }
      } else {
        _initializeWhiteCanvas();
      }
    } catch (e) {
      _initializeWhiteCanvas();
    }
    _pixelsChangedController.add(null);
  }

  void _initializeWhiteCanvas() {
    for (int i = 0; i < pixels.length; i += 4) {
      pixels[i] = 255;     // R
      pixels[i + 1] = 255; // G
      pixels[i + 2] = 255; // B
      pixels[i + 3] = 255; // A
    }
  }

  void invertPixel(int x, int y) {
    if (x >= 0 && x < canvasWidth && y >= 0 && y < canvasHeight) {
      int index = (y * canvasWidth + x) * 4;
      pixels[index] = 255;    // Red (full intensity)
      pixels[index + 1] = 0;  // Green
      pixels[index + 2] = 0;  // Blue
      pixels[index + 3] = 255; // Alpha (fully opaque)
      
      _pixelsChangedController.add(null);
      
      // Add to update queue
      String pixelCoord = '${y.toString().padLeft(3, '0')}${x.toString().padLeft(3, '0')}';
      if (!_pixelUpdateQueue.contains(pixelCoord)) {
        _pixelUpdateQueue.addLast(pixelCoord);
        _processPixelUpdateQueue(); // Try to process immediately if possible
      }
    }
  }

  void dispose() {
    _channel.sink.close();
    _updateTimer?.cancel();
    _pixelsChangedController.close();
  }
}
