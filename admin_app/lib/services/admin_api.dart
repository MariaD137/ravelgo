import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:ravelgo_admin/services/auth_session.dart';

class AdminApiException implements Exception {
  final String message;
  const AdminApiException(this.message);

  @override
  String toString() => message;
}

/// GET /api/admin/dashboard — top-line KPIs shown on the admin dashboard.
class DashboardKpis {
  final int activeTrips;
  final int onlineDrivers;
  final int pendingApprovals;

  const DashboardKpis({required this.activeTrips, required this.onlineDrivers, required this.pendingApprovals});

  factory DashboardKpis.fromJson(Map<String, dynamic> json) => DashboardKpis(
        activeTrips: (json['activeTrips'] as num?)?.toInt() ?? 0,
        onlineDrivers: (json['onlineDrivers'] as num?)?.toInt() ?? 0,
        pendingApprovals: (json['pendingApprovals'] as num?)?.toInt() ?? 0,
      );
}

class FleetCounts {
  final int total;
  final int online;
  final int offline;
  final int active;
  final int pendingReview;
  final int suspended;

  const FleetCounts({
    required this.total,
    required this.online,
    required this.offline,
    required this.active,
    required this.pendingReview,
    required this.suspended,
  });

  factory FleetCounts.fromJson(Map<String, dynamic> json) => FleetCounts(
        total: (json['total'] as num?)?.toInt() ?? 0,
        online: (json['online'] as num?)?.toInt() ?? 0,
        offline: (json['offline'] as num?)?.toInt() ?? 0,
        active: (json['active'] as num?)?.toInt() ?? 0,
        pendingReview: (json['pendingReview'] as num?)?.toInt() ?? 0,
        suspended: (json['suspended'] as num?)?.toInt() ?? 0,
      );
}

/// One row of GET /api/admin/drivers/presence's driver list. [location] is
/// either a lat/lng map or the literal string "Location unavailable" —
/// never fabricated coordinates, so it's kept as the raw dynamic value and
/// only formatted for display where it's shown.
class FleetDriver {
  final String id;
  final String name;
  final String email;
  final String status;
  final bool isOnline;
  final DateTime? onlineSince;
  final String? vehicle;
  final dynamic location;

  const FleetDriver({
    required this.id,
    required this.name,
    required this.email,
    required this.status,
    required this.isOnline,
    required this.onlineSince,
    required this.vehicle,
    required this.location,
  });

  String get locationLabel {
    if (location is Map && location['lat'] != null && location['lng'] != null) {
      return '${(location['lat'] as num).toStringAsFixed(4)}, ${(location['lng'] as num).toStringAsFixed(4)}';
    }
    return 'Location unavailable';
  }

  factory FleetDriver.fromJson(Map<String, dynamic> json) => FleetDriver(
        id: json['id'] as String,
        name: json['name'] as String,
        email: json['email'] as String,
        status: json['status'] as String,
        isOnline: json['isOnline'] as bool? ?? false,
        onlineSince: json['onlineSince'] == null ? null : DateTime.tryParse(json['onlineSince'] as String),
        vehicle: json['vehicle'] as String?,
        location: json['location'],
      );
}

class FleetPresence {
  final FleetCounts counts;
  final List<FleetDriver> drivers;

  const FleetPresence({required this.counts, required this.drivers});

  factory FleetPresence.fromJson(Map<String, dynamic> json) => FleetPresence(
        counts: FleetCounts.fromJson(json['counts'] as Map<String, dynamic>),
        drivers: ((json['drivers'] as List?) ?? [])
            .map((d) => FleetDriver.fromJson(d as Map<String, dynamic>))
            .toList(),
      );
}

/// HTTP client for the admin-facing parts of the backend
/// (backend/src/routes/admin.routes.ts) — dashboard KPIs and fleet-wide
/// driver presence. Every call requires an Admin-role bearer token; the
/// backend independently re-enforces that on every request regardless of
/// what this client sends.
class AdminApi {
  final String baseUrl;
  final AuthTokenProvider authTokenProvider;
  final http.Client _client;

  AdminApi({required this.baseUrl, required this.authTokenProvider, http.Client? client})
      : _client = client ?? http.Client();

  Future<Map<String, String>> _authHeaders() async {
    final token = await authTokenProvider.getAccessToken();
    if (token == null) {
      throw const AdminApiException('You need to sign in again.');
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
      // Not the standardized {error:{message}} shape — use the fallback.
    }
    return fallback;
  }

  Future<DashboardKpis> fetchDashboardKpis() async {
    final http.Response res;
    try {
      res = await _client.get(Uri.parse('$baseUrl/api/admin/dashboard'), headers: await _authHeaders());
    } on AdminApiException {
      rethrow;
    } catch (_) {
      throw const AdminApiException('Unable to load dashboard');
    }
    if (res.statusCode != 200) throw AdminApiException(_errorMessage(res, 'Unable to load dashboard'));
    return DashboardKpis.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<FleetPresence> fetchFleetPresence() async {
    final http.Response res;
    try {
      res = await _client.get(Uri.parse('$baseUrl/api/admin/drivers/presence'), headers: await _authHeaders());
    } on AdminApiException {
      rethrow;
    } catch (_) {
      throw const AdminApiException('Unable to load fleet presence');
    }
    if (res.statusCode != 200) throw AdminApiException(_errorMessage(res, 'Unable to load fleet presence'));
    return FleetPresence.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }
}
