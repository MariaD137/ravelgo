import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:ravelgo_user_app/services/auth_service.dart';

/// Thrown for any non-2xx backend response, carrying a human-readable message.
class ApiException implements Exception {
  final int statusCode;
  final String message;
  ApiException(this.statusCode, this.message);
  @override
  String toString() => message;
}

/// The single HTTP client every screen uses to reach the RavelGo backend.
/// Attaches the signed-in user's Cognito ACCESS token as a Bearer header
/// (the backend verifies access tokens — see backend/src/middleware/auth.ts)
/// and points at API_BASE_URL from the app's .env.
class ApiClient {
  static String get _base {
    final b = (dotenv.env['API_BASE_URL'] ?? '').trim();
    return b.endsWith('/') ? b.substring(0, b.length - 1) : b;
  }

  static bool get isConfigured => _base.isNotEmpty && !_base.contains('example.com');

  static Uri _uri(String path) => Uri.parse('$_base$path');

  static Future<Map<String, String>> _headers() async {
    final token = await AuthService.validAccessToken();
    return {
      'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  static Future<dynamic> get(String path) async =>
      _handle(await http.get(_uri(path), headers: await _headers()));

  static Future<dynamic> post(String path, [Object? body]) async => _handle(
        await http.post(_uri(path), headers: await _headers(), body: body == null ? null : jsonEncode(body)),
      );

  static Future<dynamic> patch(String path, [Object? body]) async => _handle(
        await http.patch(_uri(path), headers: await _headers(), body: body == null ? null : jsonEncode(body)),
      );

  static Future<dynamic> delete(String path, [Object? body]) async => _handle(
        await http.delete(_uri(path), headers: await _headers(), body: body == null ? null : jsonEncode(body)),
      );

  static dynamic _handle(http.Response res) {
    dynamic decoded;
    if (res.body.isNotEmpty) {
      try {
        decoded = jsonDecode(res.body);
      } catch (_) {
        decoded = res.body;
      }
    }
    if (res.statusCode >= 200 && res.statusCode < 300) return decoded;

    final msg = (decoded is Map && decoded['error'] != null)
        ? decoded['error'].toString()
        : 'Request failed (${res.statusCode})';
    throw ApiException(res.statusCode, msg);
  }
}
