import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

import 'auth_provider.dart';

/// A backend error response, thrown for any non-2xx result. Carries the
/// backend's own error shape so callers can branch on [code] without
/// re-parsing raw JSON themselves — e.g. a 409 with `code: "DRIVER_BUSY"`
/// or `code: "RENTAL_OVERLAP"`.
class ApiException implements Exception {
  ApiException({required this.statusCode, required this.message, this.code, this.body});

  final int statusCode;
  final String? code;
  final String message;
  final Map<String, dynamic>? body;

  @override
  String toString() => 'ApiException($statusCode${code != null ? ", $code" : ""}): $message';
}

/// Thin, shared HTTP wrapper used by every domain API class (ride_api.dart,
/// courier_api.dart, rental_api.dart, pricing_api.dart, ...) instead of each
/// calling package:http directly. Resolves the backend base URL from .env
/// (API_BASE_URL — declared in .env.example), attaches the caller's bearer
/// token via [AuthProvider], and turns a non-2xx response, a network
/// failure, a timeout, or a malformed response into a single, uniformly
/// catchable [ApiException]. Auth, base URL resolution, and error handling
/// all live in exactly this one place — mirrors driver_app's ApiClient
/// (see that file's own history for why this shape was chosen).
class ApiClient {
  ApiClient({AuthProvider? authProvider, http.Client? httpClient, Duration? timeout})
    : _authProvider = authProvider ?? DevOnlyAuthProvider.instance,
      _http = httpClient ?? http.Client(),
      _timeout = timeout ?? const Duration(seconds: 20);

  final AuthProvider _authProvider;
  final http.Client _http;
  final Duration _timeout;

  // dotenv.env throws NotInitializedError if dotenv.load() was never
  // called (e.g. a unit test that constructs ApiClient directly without
  // going through main()'s startup sequence) — fall back to an empty base
  // URL rather than letting an unrelated dotenv exception surface from
  // every API call.
  String get _baseUrl => dotenv.isInitialized ? (dotenv.env['API_BASE_URL'] ?? '') : '';

  Future<Map<String, String>> _headers() async {
    final token = await _authProvider.getAccessToken();
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
    return _send(() async => _http.get(_uri(path, query), headers: await _headers()));
  }

  Future<dynamic> post(String path, {Object? body}) async {
    return _send(() async => _http.post(_uri(path), headers: await _headers(), body: jsonEncode(body)));
  }

  Future<dynamic> patch(String path, {Object? body}) async {
    return _send(() async => _http.patch(_uri(path), headers: await _headers(), body: jsonEncode(body)));
  }

  /// Runs one HTTP call and turns every failure mode into an [ApiException]
  /// so every call site's `on ApiException catch` handles all of them
  /// uniformly — a non-2xx response (via [_handle]), no connectivity at all
  /// (SocketException), a request that never got a response in time
  /// (TimeoutException), and a malformed response body (FormatException,
  /// from jsonDecode in [_handle]) all reach the caller the same way,
  /// distinguishable by [ApiException.code] (`NETWORK_ERROR` / `TIMEOUT` /
  /// `INVALID_RESPONSE`) rather than three different exception types a
  /// screen would otherwise need three different catch clauses for.
  Future<dynamic> _send(Future<http.Response> Function() request) async {
    try {
      final res = await request().timeout(_timeout);
      return _handle(res);
    } on ApiException {
      rethrow;
    } on TimeoutException {
      throw ApiException(
        statusCode: 0,
        code: 'TIMEOUT',
        message: 'The request took too long. Check your connection and try again.',
      );
    } on SocketException {
      throw ApiException(
        statusCode: 0,
        code: 'NETWORK_ERROR',
        message: 'Could not reach the server. Check your connection and try again.',
      );
    } on FormatException {
      throw ApiException(
        statusCode: 0,
        code: 'INVALID_RESPONSE',
        message: 'The server sent back something unexpected.',
      );
    }
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
