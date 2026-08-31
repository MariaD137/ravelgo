import 'dart:async';
import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:ravelgo_driver_app/services/auth_service.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Driver-side realtime client. Opens the backend WebSocket (`/ws`) and pushes
/// the driver's location with `{type:"location", lat, lng}`; the backend fans
/// it out to whoever is subscribed to the driver's active trips (the rider).
class RealtimeService {
  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  bool _open = false;

  static bool get isConfigured {
    final b = (dotenv.env['API_BASE_URL'] ?? '').trim();
    return b.isNotEmpty && !b.contains('example.com');
  }

  static String? _wsBase() {
    var base = (dotenv.env['API_BASE_URL'] ?? '').trim();
    if (base.isEmpty) return null;
    if (base.endsWith('/')) base = base.substring(0, base.length - 1);
    return base.replaceFirst('https://', 'wss://').replaceFirst('http://', 'ws://');
  }

  Future<bool> connect() async {
    final token = await AuthService.validAccessToken();
    if (token == null || token.isEmpty) return false;
    final base = _wsBase();
    if (base == null) return false;
    try {
      // Token carried in the WebSocket subprotocol header, not the URL.
      _channel = WebSocketChannel.connect(Uri.parse('$base/ws'), protocols: ['bearer', token]);
      _open = true;
    } catch (_) {
      return false;
    }
    // Drain incoming frames (acks/errors) so the stream stays healthy.
    _sub = _channel!.stream.listen((_) {}, onError: (_) => _open = false, onDone: () => _open = false);
    return true;
  }

  void sendLocation(double lat, double lng) {
    if (!_open) return;
    _channel?.sink.add(jsonEncode({'type': 'location', 'lat': lat, 'lng': lng}));
  }

  void dispose() {
    _open = false;
    _sub?.cancel();
    _channel?.sink.close();
    _channel = null;
  }
}
