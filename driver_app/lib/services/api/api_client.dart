import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

import 'auth_token_provider.dart';

/// A backend error response, thrown for any non-2xx result. Carries the
/// backend's own error shape — including the DRIVER_BUSY conflict format
/// (`{code, message, activeAssignmentType, activeAssignmentId}`) that
/// services/driver-availability.ts on the backend returns for a 409 — so
/// callers can branch on [code] without re-parsing raw JSON themselves.
class ApiException implements Exception {
  ApiException({required this.statusCode, required this.message, this.code, this.body});

  final int statusCode;
  final String? code;
  final String message;
  final Map<String, dynamic>? body;

  @override
  String toString() => 'ApiException($statusCode${code != null ? ", $code" : ""}): $message';
}

/// Thin, shared HTTP wrapper used by every domain API class
/// (ride_api.dart, courier_api.dart, driver_api.dart, ...) instead of each
/// calling package:http directly. Resolves the backend base URL from .env
/// (API_BASE_URL — already declared in .env.example, unused until this
/// change), attaches the caller's bearer token via [AuthTokenProvider], and
/// turns a non-2xx response into an [ApiException]. Auth, base URL
/// resolution, and error handling all live in exactly this one place.
class ApiClient {
  ApiClient({AuthTokenProvider? tokenProvider, http.Client? httpClient})
    : _tokenProvider = tokenProvider ?? InMemoryAuthTokenProvider.instance,
      _http = httpClient ?? http.Client();

  final AuthTokenProvider _tokenProvider;
  final http.Client _http;

  String get _baseUrl => dotenv.env['API_BASE_URL'] ?? '';

  Future<Map<String, String>> _headers() async {
    final token = await _tokenProvider.getAccessToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Uri _uri(String path, [Map<String, dynamic>? query]) {
    final base = Uri.parse('$_baseUrl$path');
    if (query == null || query.isEmpty) return base;
    return base.replace(queryParameters: query.map((key, value) => MapEntry(key, '$value')));
  }

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) async {
    final res = await _http.get(_uri(path, query), headers: await _headers());
    return _handle(res);
  }

  Future<dynamic> post(String path, {Object? body}) async {
    final res = await _http.post(_uri(path), headers: await _headers(), body: jsonEncode(body));
    return _handle(res);
  }

  Future<dynamic> patch(String path, {Object? body}) async {
    final res = await _http.patch(_uri(path), headers: await _headers(), body: jsonEncode(body));
    return _handle(res);
  }

  dynamic _handle(http.Response res) {
    final decoded = res.body.isEmpty ? null : jsonDecode(res.body);
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return decoded;
    }
    final map = decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    throw ApiException(
      statusCode: res.statusCode,
      code: map['code'] as String?,
      message: (map['message'] ?? map['error'] ?? 'Request failed').toString(),
      body: map,
    );
  }
}
