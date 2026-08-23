import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

import 'auth_provider.dart';

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
/// change), attaches the caller's bearer token via [AuthProvider], and
/// turns a non-2xx response into an [ApiException]. Auth, base URL
/// resolution, and error handling all live in exactly this one place.
class ApiClient {
  // The default here is [createDefaultAuthProvider], never
  // DevOnlyAuthProvider directly — a bare ApiClient() must be safe to
  // construct in every build mode. DriverSession (and the equivalent
  // composition point in every other app) still passes an explicit
  // [AuthProvider] rather than relying on this default; it exists so no
  // *other* accidental bare construction can crash a release build either.
  ApiClient({AuthProvider? authProvider, http.Client? httpClient, Duration? timeout, this.onUnauthorized})
    : _authProvider = authProvider ?? createDefaultAuthProvider(),
      _http = httpClient ?? http.Client(),
      _timeout = timeout ?? const Duration(seconds: 20);

  final AuthProvider _authProvider;
  final http.Client _http;
  final Duration _timeout;

  /// Invoked whenever a request comes back 401, before the [ApiException]
  /// is thrown — the composition root wires this to the session's sign-out
  /// path so an expired/revoked token clears local auth state instead of
  /// leaving the UI showing a session that no longer exists server-side.
  /// Token ownership stays inside this layer either way: callers only ever
  /// see [ApiException], never the token itself.
  final void Function()? onUnauthorized;

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

  /// Resolves a possibly-relative asset URL (e.g. a Vehicle.imageUrl like
  /// "/demo-assets/demo-bmw-7-series.png" from a seeded demo vehicle)
  /// against API_BASE_URL, the same way every REST path already is. A real
  /// driver-uploaded photo comes back as an absolute CloudFront URL (see
  /// backend/src/services/assets.ts) and is returned unchanged. Null/empty
  /// input returns null, so callers can pass Vehicle.imageUrl straight
  /// through without a null check first.
  String? resolveAssetUrl(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
    return '$_baseUrl$raw';
  }

  /// The wss:// (or ws:// for a plain-http backend, e.g. local dev)
  /// equivalent of [path] against the same API_BASE_URL every REST call
  /// uses — see docs/realtime-architecture.md's wire protocol
  /// (`wss://<host>/ws?token=<access token>`) on the backend.
  Uri wsUri(String path) {
    final httpUri = Uri.parse('$_baseUrl$path');
    final wsScheme = httpUri.scheme == 'https' ? 'wss' : 'ws';
    return httpUri.replace(scheme: wsScheme);
  }

  /// The same [AuthProvider] this client attaches to every REST request's
  /// Authorization header — exposed so a caller opening a WebSocket
  /// connection (which authenticates via a `token` query param instead of
  /// a header) can use the identical token source rather than a second one.
  Future<String?> getAccessToken() => _authProvider.getAccessToken();

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) async {
    return _send(() async => _http.get(_uri(path, query), headers: await _headers()));
  }

  // body is only jsonEncode'd when actually provided — jsonEncode(null)
  // would otherwise send the 4-byte literal "null" as the request body,
  // which Express's strict-mode JSON parser rejects with 400 before the
  // route handler ever runs. Every no-payload action (accept/decline an
  // offer, cancel, process, ...) needs a genuinely empty body, same as
  // [get] and [delete] already send.
  Future<dynamic> post(String path, {Object? body}) async {
    return _send(() async => _http.post(_uri(path), headers: await _headers(), body: body == null ? null : jsonEncode(body)));
  }

  Future<dynamic> patch(String path, {Object? body}) async {
    return _send(() async => _http.patch(_uri(path), headers: await _headers(), body: body == null ? null : jsonEncode(body)));
  }

  /// Runs one HTTP call and turns every failure mode into an [ApiException]
  /// so every call site's `on ApiException catch` handles all of them
  /// uniformly — a non-2xx response (via [_handle]), no connectivity at all
  /// (SocketException), a request that never got a response in time
  /// (TimeoutException), and a malformed response body (FormatException,
  /// from jsonDecode in [_handle]) all reach the caller the same way,
  /// distinguishable by [ApiException.code] (`NETWORK_ERROR` /
  /// `TIMEOUT` / `INVALID_RESPONSE`) rather than three different exception
  /// types a screen would otherwise need three different catch clauses for.
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
    if (res.statusCode == 401) onUnauthorized?.call();
    throw ApiException(
      statusCode: res.statusCode,
      code: map['code'] as String?,
      message: (map['message'] ?? map['error'] ?? 'Request failed').toString(),
      body: map,
    );
  }
}
