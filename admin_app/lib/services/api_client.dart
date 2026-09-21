import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:ravelgo_admin/services/auth_service.dart';
import 'package:ravelgo_admin/services/session_guard.dart';

/// Thrown for any non-2xx backend response, carrying a human-readable message.
///
/// [statusCode] 0 means the request never reached the backend at all (no
/// network, DNS failure, TLS failure, a wrong API_BASE_URL) — a connection
/// problem, not an answer from the backend, and screens must never present
/// it as one. Everything else is a real HTTP status the backend chose.
class ApiException implements Exception {
  final int statusCode;
  final String message;

  /// The backend's machine-readable error code from its `{error: {code, ...}}`
  /// envelope (backend/src/lib/errors.ts), when it sent one. Used to decide
  /// whether a 5xx message is one the backend meant a person to read — see
  /// [describeApiFailure].
  final String? code;

  ApiException(this.statusCode, this.message, {this.code});

  bool get isNetworkFailure => statusCode == 0;
  bool get isUnauthenticated => statusCode == 401;
  bool get isForbidden => statusCode == 403;
  bool get isNotFound => statusCode == 404;
  bool get isServerError => statusCode >= 500;

  /// Error codes whose message the backend writes FOR the reader and keeps
  /// free of internals — safe to show verbatim on a 5xx. Everything else
  /// falls back to a generic sentence, so a future 5xx carrying a dynamic
  /// message under some other code can never leak through this path.
  ///
  /// This exists because a real outage was made harder to diagnose by the
  /// apps: the backend said "Database schema is out of date on this server
  /// (pending migrations not applied)" and every screen replaced it with
  /// "RavelGo had a server problem (500)", hiding the one fact that would
  /// have pointed straight at the cause.
  static const _readableServerCodes = {
    'DATABASE_ERROR',
    'PAYMENT_PROVIDER_ERROR',
    'SERVICE_UNAVAILABLE',
    'UPSTREAM_ERROR',
  };

  /// Whether this failure carries a server-side explanation worth showing.
  bool get hasReadableServerReason =>
      isServerError && code != null && _readableServerCodes.contains(code) && message.trim().isNotEmpty;

  @override
  String toString() => message;
}

/// The single HTTP client every admin screen uses to reach the RavelGo
/// backend. Attaches the signed-in admin's Cognito ACCESS token as a Bearer
/// header and points at API_BASE_URL from the app's .env.
class ApiClient {
  static String get _base {
    final b = (dotenv.env['API_BASE_URL'] ?? '').trim();
    return b.endsWith('/') ? b.substring(0, b.length - 1) : b;
  }

  static bool get isConfigured =>
      _base.isNotEmpty && !_base.contains('example.com');

  static Uri _uri(String path) => Uri.parse('$_base$path');

  /// Swappable for tests (package:http/testing.dart's MockClient).
  static http.Client client = http.Client();

  static Future<Map<String, String>> _headers() async {
    final token = await AuthService.validAccessToken();
    return {
      'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  static Future<dynamic> get(String path) => _send('GET', path, null);
  static Future<dynamic> post(String path, [Object? body]) =>
      _send('POST', path, body);
  static Future<dynamic> patch(String path, [Object? body]) =>
      _send('PATCH', path, body);
  static Future<dynamic> delete(String path, [Object? body]) =>
      _send('DELETE', path, body);

  static Future<dynamic> _send(String method, String path, Object? body) async {
    var res = await _request(method, path, body);
    // One app-wide rule for an expired/revoked session (see SessionGuard):
    // force a refresh, retry once, and otherwise hand the user back to the
    // sign-in screen instead of leaving them on a screen that can no longer
    // load anything.
    if (res.statusCode == 401) {
      if (await SessionGuard.tryRefresh()) {
        res = await _request(method, path, body);
      }
      if (res.statusCode == 401) {
        await SessionGuard.expire();
        throw ApiException(401, SessionGuard.expiredMessage);
      }
    }
    return _handle(res);
  }

  static Future<http.Response> _request(
    String method,
    String path,
    Object? body,
  ) async {
    final headers = await _headers();
    final encoded = body == null ? null : jsonEncode(body);
    try {
      switch (method) {
        case 'GET':
          return await client.get(_uri(path), headers: headers);
        case 'POST':
          return await client.post(_uri(path), headers: headers, body: encoded);
        case 'PATCH':
          return await client.patch(
            _uri(path),
            headers: headers,
            body: encoded,
          );
        default:
          return await client.delete(
            _uri(path),
            headers: headers,
            body: encoded,
          );
      }
      // A request that never reaches the backend is not a backend answer.
      // Left unclassified, these surfaced as a raw
      // "ClientException: Failed to fetch, uri=..." in the UI.
    } on SocketException catch (e) {
      throw ApiException(
        0,
        'Can\'t reach RavelGo (${e.osError?.message ?? e.message}). Check your connection and try again.',
      );
    } on http.ClientException catch (e) {
      throw ApiException(
        0,
        'Can\'t reach RavelGo (${e.message}). Check your connection and try again.',
      );
    }
  }

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

    throw ApiException(
      res.statusCode,
      _extractMessage(decoded, res.statusCode),
      code: _extractCode(decoded),
    );
  }

  /// Backend errors come in two shapes: most route handlers reply with
  /// `{error: "plain string"}`, while the global error-handler middleware
  /// (and classified Prisma errors) reply with a nested
  /// `{error: {code, message, details, timestamp}}`. Without this, the
  /// nested shape fell through to `.toString()` on a raw Map and showed a
  /// dump like "{code: INTERNAL_SERVER_ERROR, message: ...}" instead of the
  /// human-readable message.
  static String _extractMessage(dynamic decoded, int statusCode) {
    if (decoded is Map) {
      final error = decoded['error'];
      if (error is Map && error['message'] != null) {
        return error['message'].toString();
      }
      if (error is String && error.isNotEmpty) return error;
      if (error != null) return error.toString();
    }
    return 'Request failed ($statusCode)';
  }

  /// The backend's error code, when its envelope carried one.
  static String? _extractCode(dynamic decoded) {
    if (decoded is Map) {
      final error = decoded['error'];
      if (error is Map && error['code'] != null) return error['code'].toString();
    }
    return null;
  }
}

/// One user-facing sentence per failure CLASS. Each class is a different
/// problem with a different remedy, and a screen that collapses them into a
/// single "Something went wrong" tells the user nothing about which one they
/// are actually looking at:
///
///   0    the request never got an answer   -> connection/config problem
///   401  the session is gone               -> sign in again
///   403  the backend refused this account  -> not allowed to do this
///   404  no such record                    -> nothing to show
///   5xx  the backend/database failed       -> server problem, retry later
String describeApiFailure(Object error, {String what = 'this'}) {
  if (error is! ApiException) {
    return 'Something went wrong loading $what. Please try again.';
  }
  if (error.isNetworkFailure) return error.message;
  switch (error.statusCode) {
    case 401:
      return SessionGuard.expiredMessage;
    case 403:
      return 'Your admin role doesn\'t have permission for $what.';
    case 404:
      return 'We couldn\'t find $what.';
    default:
      if (error.isServerError) {
        // When the backend has told us WHY in its own words, show that
        // instead of a generic sentence — it is written for a person and
        // carries no internals (see ApiException.hasReadableServerReason).
        // A real outage was prolonged by collapsing
        // "Database schema is out of date on this server (pending migrations
        // not applied)" into "server problem (500)".
        if (error.hasReadableServerReason) return error.message;
        return 'RavelGo had a server problem loading $what (${error.statusCode}). Please try again in a moment.';
      }
      return error.message;
  }
}
