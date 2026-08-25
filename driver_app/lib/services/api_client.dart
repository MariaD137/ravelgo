import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:ravelgo_driver_app/services/auth_service.dart';

class ApiException implements Exception {
  final int statusCode;
  final String message;
  final Map<String, dynamic>? body;

  ApiException(this.statusCode, this.message, {this.body});

  @override
  String toString() => 'ApiException($statusCode): $message';
}

/// Internal-only: signals that a request hit a 401 and the caller should
/// refresh and retry once, rather than surfacing to the UI. Never escapes
/// _sendWithRetry.
class _NeedsRefreshException implements Exception {}

class ApiClient {
  static final ApiClient _instance = ApiClient._();
  factory ApiClient() => _instance;
  ApiClient._();

  final HttpClient _http = HttpClient();
  static const _timeout = Duration(seconds: 15);

  String get _baseUrl {
    final url = dotenv.env['API_BASE_URL'];
    if (url == null || url.isEmpty) {
      throw StateError('API_BASE_URL is not set in .env');
    }
    return url;
  }

  Future<Map<String, String>> _authHeaders() async {
    final token = await AuthService().getAccessToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Future<dynamic> get(String path, {Map<String, String>? queryParams}) {
    return _sendWithRetry(() async {
      final uri = Uri.parse('$_baseUrl/api$path').replace(queryParameters: queryParams);
      final request = await _http.getUrl(uri).timeout(_timeout);
      final headers = await _authHeaders();
      headers.forEach((k, v) => request.headers.set(k, v));
      return request.close().timeout(_timeout);
    });
  }

  Future<dynamic> post(String path, {Map<String, dynamic>? body}) {
    return _sendWithRetry(() async {
      final uri = Uri.parse('$_baseUrl/api$path');
      final request = await _http.postUrl(uri).timeout(_timeout);
      final headers = await _authHeaders();
      headers.forEach((k, v) => request.headers.set(k, v));
      if (body != null) request.write(jsonEncode(body));
      return request.close().timeout(_timeout);
    });
  }

  Future<dynamic> patch(String path, {Map<String, dynamic>? body}) {
    return _sendWithRetry(() async {
      final uri = Uri.parse('$_baseUrl/api$path');
      final request = await _http.patchUrl(uri).timeout(_timeout);
      final headers = await _authHeaders();
      headers.forEach((k, v) => request.headers.set(k, v));
      if (body != null) request.write(jsonEncode(body));
      return request.close().timeout(_timeout);
    });
  }

  Future<dynamic> delete(String path) {
    return _sendWithRetry(() async {
      final uri = Uri.parse('$_baseUrl/api$path');
      final request = await _http.deleteUrl(uri).timeout(_timeout);
      final headers = await _authHeaders();
      headers.forEach((k, v) => request.headers.set(k, v));
      return request.close().timeout(_timeout);
    });
  }

  /// Runs [attempt] (one full request+response cycle, using whatever
  /// access token is stored at call time), and on a 401 refreshes the
  /// session and runs [attempt] exactly once more with the refreshed
  /// token. Never retries more than once — a 401 immediately after a
  /// successful refresh surfaces as a real error rather than looping.
  /// Network failures (no server response at all) and a failed refresh
  /// both produce a clear ApiException instead of a raw platform
  /// exception leaking to the UI.
  Future<dynamic> _sendWithRetry(Future<HttpClientResponse> Function() attempt) async {
    try {
      return await _handleResponse(await attempt());
    } on _NeedsRefreshException {
      final refreshed = await AuthService().refreshSession();
      if (!refreshed) {
        await AuthService().signOut();
        throw ApiException(401, 'Your session has expired. Please sign in again.');
      }
      try {
        return await _handleResponse(await attempt());
      } on _NeedsRefreshException {
        // The refreshed token was itself rejected — don't loop again.
        await AuthService().signOut();
        throw ApiException(401, 'Your session has expired. Please sign in again.');
      }
    } on TimeoutException {
      throw ApiException(0, 'The request timed out. Please try again.');
    } on SocketException {
      throw ApiException(0, 'Network error. Check your connection and try again.');
    } on HttpException {
      throw ApiException(0, 'Network error. Check your connection and try again.');
    }
  }

  Future<dynamic> _handleResponse(HttpClientResponse response) async {
    final rawBody = await response.transform(utf8.decoder).join().timeout(_timeout);
    final statusCode = response.statusCode;

    if (statusCode == 401) {
      throw _NeedsRefreshException();
    }

    dynamic decoded;
    if (rawBody.isNotEmpty) {
      try {
        decoded = jsonDecode(rawBody);
      } on FormatException {
        if (statusCode >= 200 && statusCode < 300) {
          throw ApiException(statusCode, 'The server returned an unexpected response. Please try again.');
        }
        decoded = null;
      }
    }

    if (statusCode >= 200 && statusCode < 300) return decoded;

    final message = decoded is Map
        ? (decoded['error']?['message'] ?? decoded['error'] ?? _defaultMessageFor(statusCode))
        : _defaultMessageFor(statusCode);
    throw ApiException(statusCode, message.toString(), body: decoded is Map<String, dynamic> ? decoded : null);
  }

  String _defaultMessageFor(int statusCode) {
    switch (statusCode) {
      case 400:
        return 'That request was invalid. Please check the details and try again.';
      case 403:
        return "You don't have permission to do that.";
      case 404:
        return 'Not found.';
      case 409:
        return 'This conflicts with the current state — please refresh and try again.';
      case 422:
        return 'Some of the information provided is invalid.';
      case 429:
        return 'Too many requests. Please wait a moment and try again.';
      default:
        if (statusCode >= 500) return 'The server ran into a problem. Please try again shortly.';
        return 'Request failed.';
    }
  }
}
