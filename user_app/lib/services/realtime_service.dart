import 'dart:async';
import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:ravelgo_user_app/services/auth_service.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// A thin client for the backend's realtime WebSocket (`/ws`). Used to follow a
/// trip live: the backend pushes `trip:status` updates (when the driver starts
/// or completes the trip) and `location` updates (the driver's position).
///
/// Message shapes (from backend/src/realtime):
///   server -> client: {type:"subscribed", tripId}
///                     {type:"trip:status", tripId, status, finalFare}
///                     {type:"location", tripId, driverId, lat, lng, updatedAt}
///                     {type:"error", message}
class RealtimeService {
  WebSocketChannel? _channel;
  StreamSubscription? _sub;

  /// Whether the app has a real backend URL to connect to.
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

  /// Connect and start delivering decoded messages to [onMessage]. Returns true
  /// if a connection was attempted. Errors and closes are reported via
  /// [onDone] so the UI can show a disconnected state.
  Future<bool> connect({
    required void Function(Map<String, dynamic> message) onMessage,
    void Function()? onDone,
  }) async {
    final token = await AuthService.validAccessToken();
    if (token == null || token.isEmpty) return false;
    final base = _wsBase();
    if (base == null) return false;

    try {
      // The token travels in the WebSocket subprotocol header, not the URL, so
      // it isn't captured in proxy/access logs. The backend reads the value
      // after the "bearer" marker.
      _channel = WebSocketChannel.connect(Uri.parse('$base/ws'), protocols: ['bearer', token]);
    } catch (_) {
      return false;
    }
    _sub = _channel!.stream.listen(
      (raw) {
        try {
          final decoded = jsonDecode(raw.toString());
          if (decoded is Map<String, dynamic>) onMessage(decoded);
        } catch (_) {
          // Ignore malformed frames.
        }
      },
      onError: (_) => onDone?.call(),
      onDone: () => onDone?.call(),
      cancelOnError: true,
    );
    return true;
  }

  /// Subscribe to live updates for [tripId].
  void subscribe(String tripId) {
    _channel?.sink.add(jsonEncode({'type': 'subscribe', 'tripId': tripId}));
  }

  void dispose() {
    _sub?.cancel();
    _channel?.sink.close();
    _channel = null;
  }
}
