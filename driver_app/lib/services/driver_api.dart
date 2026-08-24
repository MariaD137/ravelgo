import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:ravelgo_driver_app/services/auth_session.dart';

/// Thrown for any failure talking to the backend — a non-2xx response, a
/// network error, or no signed-in session. [message] is always meant to be
/// shown to the driver as-is (it's either the backend's own error message,
/// e.g. "Your account is suspended — you can't go online.", or a plain
/// "Unable to load dashboard" for anything unexpected).
class DriverApiException implements Exception {
  final String message;
  const DriverApiException(this.message);

  @override
  String toString() => message;
}

/// The calling driver's own daily dashboard summary — mirrors
/// GET /api/drivers/me/summary. Every field here comes from the backend;
/// nothing is computed or guessed client-side.
class DriverSummary {
  final bool isOnline;
  final DateTime? lastOnlineAt;
  final int tripsToday;
  final double grossFareToday;
  final double platformFeeToday;
  final double netEarningsToday;
  final double onlineHoursToday;
  final double rating;
  final int totalTrips;

  const DriverSummary({
    required this.isOnline,
    required this.lastOnlineAt,
    required this.tripsToday,
    required this.grossFareToday,
    required this.platformFeeToday,
    required this.netEarningsToday,
    required this.onlineHoursToday,
    required this.rating,
    required this.totalTrips,
  });

  bool get hasActivityToday => tripsToday > 0 || onlineHoursToday > 0;

  factory DriverSummary.fromJson(Map<String, dynamic> json) {
    return DriverSummary(
      isOnline: json['isOnline'] as bool? ?? false,
      lastOnlineAt: json['lastOnlineAt'] == null ? null : DateTime.tryParse(json['lastOnlineAt'] as String),
      tripsToday: (json['tripsToday'] as num?)?.toInt() ?? 0,
      grossFareToday: (json['grossFareToday'] as num?)?.toDouble() ?? 0,
      platformFeeToday: (json['platformFeeToday'] as num?)?.toDouble() ?? 0,
      netEarningsToday: (json['netEarningsToday'] as num?)?.toDouble() ?? 0,
      onlineHoursToday: (json['onlineHoursToday'] as num?)?.toDouble() ?? 0,
      rating: (json['rating'] as num?)?.toDouble() ?? 0,
      totalTrips: (json['totalTrips'] as num?)?.toInt() ?? 0,
    );
  }
}

/// HTTP client for the driver-facing parts of the backend's Drivers API
/// (backend/src/routes/drivers.routes.ts). Every request is scoped to the
/// authenticated driver via the bearer token — there is deliberately no
/// method here that takes a driver id, matching the backend's /drivers/me
/// semantics (a driver can never address another driver's data by id).
class DriverApi {
  final String baseUrl;
  final AuthTokenProvider authTokenProvider;
  final http.Client _client;

  DriverApi({required this.baseUrl, required this.authTokenProvider, http.Client? client})
      : _client = client ?? http.Client();

  Future<Map<String, String>> _authHeaders() async {
    final token = await authTokenProvider.getAccessToken();
    if (token == null) {
      throw const DriverApiException('You need to sign in again.');
    }
    return {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'};
  }

  String _errorMessage(http.Response res, String fallback) {
    try {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final error = body['error'];
      if (error is Map<String, dynamic> && error['message'] is String) return error['message'] as String;
      if (error is String) return error;
    } catch (_) {
      // Response body wasn't the standardized {error:{message}} shape —
      // fall through to the generic message below.
    }
    return fallback;
  }

  Future<DriverSummary> fetchSummary() async {
    final http.Response res;
    try {
      res = await _client.get(Uri.parse('$baseUrl/api/drivers/me/summary'), headers: await _authHeaders());
    } on DriverApiException {
      rethrow;
    } catch (_) {
      throw const DriverApiException('Unable to load dashboard');
    }

    if (res.statusCode != 200) {
      throw DriverApiException(_errorMessage(res, 'Unable to load dashboard'));
    }
    return DriverSummary.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// Sets presence on the backend and returns the confirmed state. Throws
  /// [DriverApiException] with the backend's own reason (e.g. pending
  /// review or suspended) if the toggle is rejected — callers must not
  /// flip local UI state until this resolves successfully.
  Future<bool> setOnline(bool isOnline) async {
    final http.Response res;
    try {
      res = await _client.patch(
        Uri.parse('$baseUrl/api/drivers/me/online'),
        headers: await _authHeaders(),
        body: jsonEncode({'isOnline': isOnline}),
      );
    } on DriverApiException {
      rethrow;
    } catch (_) {
      throw const DriverApiException('Unable to update your status');
    }

    if (res.statusCode != 200) {
      throw DriverApiException(_errorMessage(res, 'Unable to update your status'));
    }
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    return json['isOnline'] as bool;
  }
}
