import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:ravelgo_driver_app/services/auth_service.dart';
import 'package:ravelgo_driver_app/services/session_guard.dart';

/// Thrown for any non-2xx backend response, carrying a human-readable message.
///
/// [statusCode] 0 means the request never reached the backend (no network,
/// DNS failure, TLS failure, wrong API_BASE_URL) — a connection problem, not
/// a backend answer, and screens must not present it as one.
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

/// The single HTTP client every driver screen uses to reach the RavelGo
/// backend. Attaches the signed-in driver's Cognito ACCESS token as a Bearer
/// header and points at API_BASE_URL from the app's .env.
///
/// Driver-access recovery: the backend authorizes every Driver-only route
/// (GET /drivers/me, /documents/me, /vehicles/me, …) off the `cognito:groups`
/// claim of the access token it receives. That claim is fixed at token issue
/// time, so right after POST /drivers/apply has the SERVER add the user to
/// the "Driver" group, the token the app already holds (valid for up to an
/// hour) still lacks it and every one of those routes answers 403. When a
/// 403 arrives and the current token does not carry the Driver group, this
/// client forces ONE token refresh via the stored refresh token and, only if
/// the refreshed token now carries the group, retries the request once. The
/// backend still makes every authorization decision — nothing here grants,
/// assumes or fakes a role; it only stops the app presenting a token that is
/// known to be stale.
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

  /// Returns true if, after a forced refresh, the access token now carries
  /// the Driver group. Swappable for tests.
  static Future<bool> Function() recoverDriverAccess =
      AuthService.ensureDriverGroupOnToken;

  static const driverGroup = 'Driver';

  // A genuine non-driver (a rider who never applied) would otherwise cost a
  // Cognito refresh on every 403; one attempt per window is plenty, since the
  // shell re-checks on every profile load anyway.
  static DateTime? _lastRecoveryAttempt;
  static const _recoveryWindow = Duration(seconds: 30);

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
    if (res.statusCode == 403 && await _tryRecoverDriverAccess()) {
      res = await _request(method, path, body);
    }
    // One app-wide rule for an expired/revoked session (see SessionGuard):
    // force a refresh, retry once, and otherwise hand the driver back to the
    // sign-in screen instead of leaving them on a screen that can no longer
    // load anything. Distinct from the 403 recovery above, which is about a
    // token that is valid but does not yet carry the Driver group.
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

  static Future<bool> _tryRecoverDriverAccess() async {
    if (AuthService.hasGroup(driverGroup)) {
      return false; // a real 403 for a driver — not a stale token
    }
    final now = DateTime.now();
    final last = _lastRecoveryAttempt;
    if (last != null && now.difference(last) < _recoveryWindow) {
      return false;
    }
    _lastRecoveryAttempt = now;
    try {
      return await recoverDriverAccess();
    } catch (_) {
      return false;
    }
  }

  /// Test hook: forget the recovery rate limit.
  static void resetRecoveryWindow() => _lastRecoveryAttempt = null;

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
  /// `{error: {code, message, details, timestamp}}`.
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

/// One user-facing sentence per failure CLASS, for a Driver-only screen
/// (documents, vehicles, profile). Each class is a different problem with a
/// different remedy, and only one of them means "this account isn't a
/// driver" — the others must never be shown as that:
///
///   401  the session is gone (token expired/revoked, or none)  → sign in again
///   403  the backend refused this token for a Driver-only route → not (yet) a driver
///   404  authenticated driver, but no driver profile row yet    → application not created
///   5xx  the backend/database failed                             → server problem
///   0    the request never got an answer                         → connection/config problem
String describeApiFailure(Object error, {String what = 'this'}) {
  if (error is! ApiException) {
    return 'Something went wrong loading $what. Please try again.';
  }
  if (error.isNetworkFailure) return error.message;
  switch (error.statusCode) {
    case 401:
      return SessionGuard.expiredMessage;
    case 403:
      return 'This account doesn\'t have driver access yet. Finish your driver application from the Home screen, then try again.';
    case 404:
      return 'Your driver profile hasn\'t been created yet. Open the Home screen to start your application, then try again.';
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
