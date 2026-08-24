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

/// One row of GET /api/trips — used for the dashboard's "Recent trips" list.
class RecentTrip {
  final String id;
  final String riderName;
  final String driverName;
  final String pickup;
  final String destination;
  final double fare;

  const RecentTrip({
    required this.id,
    required this.riderName,
    required this.driverName,
    required this.pickup,
    required this.destination,
    required this.fare,
  });

  factory RecentTrip.fromJson(Map<String, dynamic> json) {
    final rider = json['rider'] as Map<String, dynamic>?;
    final driver = json['driver'] as Map<String, dynamic>?;
    final driverUser = driver?['user'] as Map<String, dynamic>?;
    return RecentTrip(
      id: json['id'] as String? ?? '',
      riderName: rider == null ? 'Unknown' : '${rider['firstName'] ?? ''} ${rider['lastName'] ?? ''}'.trim(),
      driverName: driverUser == null ? 'Unassigned' : '${driverUser['firstName'] ?? ''} ${driverUser['lastName'] ?? ''}'.trim(),
      pickup: json['pickup'] as String? ?? '',
      destination: json['destination'] as String? ?? '',
      fare: ((json['finalFare'] ?? json['estimatedFare'] ?? 0) as num).toDouble(),
    );
  }
}

class RecentTripsPage {
  final List<RecentTrip> trips;
  final int total;

  const RecentTripsPage({required this.trips, required this.total});

  factory RecentTripsPage.fromJson(Map<String, dynamic> json) => RecentTripsPage(
        trips: ((json['data'] as List?) ?? []).map((t) => RecentTrip.fromJson(t as Map<String, dynamic>)).toList(),
        total: (json['total'] as num?)?.toInt() ?? 0,
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

/// Mirrors backend/prisma/schema.prisma's DriverDocument, same shape the
/// driver app's DriverDocument model reads — an admin sees exactly the
/// same record a driver does, never a different or filtered view.
class AdminDocument {
  final String id;
  final String driverId;
  final String? vehicleId;
  final String title;
  final String documentType;
  final String status;
  final String? fileKey;
  final DateTime? expiryDate;
  final String? rejectionReason;
  final DateTime? reviewedAt;

  const AdminDocument({
    required this.id,
    required this.driverId,
    required this.vehicleId,
    required this.title,
    required this.documentType,
    required this.status,
    required this.fileKey,
    required this.expiryDate,
    required this.rejectionReason,
    required this.reviewedAt,
  });

  bool get hasFile => fileKey != null;

  factory AdminDocument.fromJson(Map<String, dynamic> json) => AdminDocument(
        id: json['id'] as String,
        driverId: json['driverId'] as String,
        vehicleId: json['vehicleId'] as String?,
        title: json['title'] as String,
        documentType: json['documentType'] as String? ?? 'OTHER',
        status: json['status'] as String? ?? 'NOT_UPLOADED',
        fileKey: json['fileKey'] as String?,
        expiryDate: json['expiryDate'] == null ? null : DateTime.tryParse(json['expiryDate'] as String),
        rejectionReason: json['rejectionReason'] as String?,
        reviewedAt: json['reviewedAt'] == null ? null : DateTime.tryParse(json['reviewedAt'] as String),
      );
}

class AdminVehiclePhoto {
  final String id;
  final String photoType;
  final String? url;

  const AdminVehiclePhoto({required this.id, required this.photoType, required this.url});

  factory AdminVehiclePhoto.fromJson(Map<String, dynamic> json) => AdminVehiclePhoto(
        id: json['id'] as String,
        photoType: json['photoType'] as String? ?? 'OTHER',
        url: json['url'] as String?,
      );
}

class AdminVehicle {
  final String id;
  final String brand;
  final String model;
  final String colour;
  final String plateNumber;
  final String year;
  final String? vin;
  final String vehicleType;
  final bool isActive;
  final String verificationStatus;
  final String? verificationReason;
  final List<AdminVehiclePhoto> photos;
  final List<AdminDocument> documents;

  const AdminVehicle({
    required this.id,
    required this.brand,
    required this.model,
    required this.colour,
    required this.plateNumber,
    required this.year,
    required this.vin,
    required this.vehicleType,
    required this.isActive,
    required this.verificationStatus,
    required this.verificationReason,
    required this.photos,
    required this.documents,
  });

  factory AdminVehicle.fromJson(Map<String, dynamic> json) => AdminVehicle(
        id: json['id'] as String,
        brand: json['brand'] as String,
        model: json['model'] as String,
        colour: json['colour'] as String,
        plateNumber: json['plateNumber'] as String,
        year: json['year'] as String,
        vin: json['vin'] as String?,
        vehicleType: json['vehicleType'] as String? ?? 'OTHER',
        isActive: json['isActive'] as bool? ?? true,
        verificationStatus: json['verificationStatus'] as String? ?? 'PENDING',
        verificationReason: json['verificationReason'] as String?,
        photos: ((json['photos'] as List?) ?? []).map((p) => AdminVehiclePhoto.fromJson(p as Map<String, dynamic>)).toList(),
        documents: ((json['documents'] as List?) ?? []).map((d) => AdminDocument.fromJson(d as Map<String, dynamic>)).toList(),
      );
}

/// GET /api/drivers (Admin list) — one row. Lighter than AdminDriverDetail;
/// vehicles here don't carry photos (the list screen doesn't need them).
class AdminDriverSummary {
  final String id;
  final String name;
  final String email;
  final String status;
  final double rating;
  final int totalTrips;
  final bool subscriptionActive;
  final List<AdminVehicle> vehicles;

  const AdminDriverSummary({
    required this.id,
    required this.name,
    required this.email,
    required this.status,
    required this.rating,
    required this.totalTrips,
    required this.subscriptionActive,
    required this.vehicles,
  });

  factory AdminDriverSummary.fromJson(Map<String, dynamic> json) {
    final user = json['user'] as Map<String, dynamic>? ?? const {};
    return AdminDriverSummary(
      id: json['id'] as String,
      name: '${user['firstName'] ?? ''} ${user['lastName'] ?? ''}'.trim(),
      email: user['email'] as String? ?? '',
      status: json['status'] as String? ?? 'PENDING_REVIEW',
      rating: (json['rating'] as num?)?.toDouble() ?? 0,
      totalTrips: (json['totalTrips'] as num?)?.toInt() ?? 0,
      subscriptionActive: json['subscriptionActive'] as bool? ?? false,
      vehicles: ((json['vehicles'] as List?) ?? []).map((v) => AdminVehicle.fromJson(v as Map<String, dynamic>)).toList(),
    );
  }
}

/// GET /api/drivers/:id (Admin detail) — full driver record with each
/// vehicle's photos and documents nested, plus driver-level documents.
class AdminDriverDetail {
  final String id;
  final String name;
  final String email;
  final String status;
  final double rating;
  final int totalTrips;
  final bool subscriptionActive;
  final List<AdminVehicle> vehicles;
  final List<AdminDocument> documents;

  const AdminDriverDetail({
    required this.id,
    required this.name,
    required this.email,
    required this.status,
    required this.rating,
    required this.totalTrips,
    required this.subscriptionActive,
    required this.vehicles,
    required this.documents,
  });

  factory AdminDriverDetail.fromJson(Map<String, dynamic> json) {
    final user = json['user'] as Map<String, dynamic>? ?? const {};
    return AdminDriverDetail(
      id: json['id'] as String,
      name: '${user['firstName'] ?? ''} ${user['lastName'] ?? ''}'.trim(),
      email: user['email'] as String? ?? '',
      status: json['status'] as String? ?? 'PENDING_REVIEW',
      rating: (json['rating'] as num?)?.toDouble() ?? 0,
      totalTrips: (json['totalTrips'] as num?)?.toInt() ?? 0,
      subscriptionActive: json['subscriptionActive'] as bool? ?? false,
      vehicles: ((json['vehicles'] as List?) ?? []).map((v) => AdminVehicle.fromJson(v as Map<String, dynamic>)).toList(),
      documents: ((json['documents'] as List?) ?? []).map((d) => AdminDocument.fromJson(d as Map<String, dynamic>)).toList(),
    );
  }
}

class PagedDrivers {
  final List<AdminDriverSummary> drivers;
  final int total;
  final int page;
  final int pageSize;

  const PagedDrivers({required this.drivers, required this.total, required this.page, required this.pageSize});

  factory PagedDrivers.fromJson(Map<String, dynamic> json) => PagedDrivers(
        drivers: ((json['data'] as List?) ?? []).map((d) => AdminDriverSummary.fromJson(d as Map<String, dynamic>)).toList(),
        total: (json['total'] as num?)?.toInt() ?? 0,
        page: (json['page'] as num?)?.toInt() ?? 1,
        pageSize: (json['pageSize'] as num?)?.toInt() ?? 20,
      );
}

/// HTTP client for the admin-facing parts of the backend
/// (backend/src/routes/admin.routes.ts, drivers.routes.ts,
/// vehicles.routes.ts, documents.routes.ts). Every call requires an
/// Admin-role bearer token; the backend independently re-enforces that on
/// every request regardless of what this client sends.
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

  Future<http.Response> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    required String fallback,
    int expectedStatus = 200,
  }) async {
    final http.Response res;
    try {
      final uri = Uri.parse('$baseUrl$path');
      final headers = await _authHeaders();
      switch (method) {
        case 'GET':
          res = await _client.get(uri, headers: headers);
          break;
        case 'PATCH':
          res = await _client.patch(uri, headers: headers, body: body == null ? null : jsonEncode(body));
          break;
        default:
          throw ArgumentError('Unsupported method $method');
      }
    } on AdminApiException {
      rethrow;
    } catch (_) {
      throw AdminApiException(fallback);
    }

    if (res.statusCode != expectedStatus) {
      throw AdminApiException(_errorMessage(res, fallback));
    }
    return res;
  }

  Future<DashboardKpis> fetchDashboardKpis() async {
    final res = await _send('GET', '/api/admin/dashboard', fallback: 'Unable to load dashboard');
    return DashboardKpis.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<FleetPresence> fetchFleetPresence() async {
    final res = await _send('GET', '/api/admin/drivers/presence', fallback: 'Unable to load fleet presence');
    return FleetPresence.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<RecentTripsPage> fetchRecentTrips({int pageSize = 5}) async {
    final res = await _send('GET', '/api/trips?pageSize=$pageSize', fallback: 'Unable to load recent trips');
    return RecentTripsPage.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<PagedDrivers> fetchDrivers({int page = 1, int pageSize = 20}) async {
    final res = await _send('GET', '/api/drivers?page=$page&pageSize=$pageSize', fallback: 'Unable to load drivers');
    return PagedDrivers.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<AdminDriverDetail> fetchDriverDetail(String driverId) async {
    final res = await _send('GET', '/api/drivers/$driverId', fallback: 'Unable to load this driver');
    return AdminDriverDetail.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<void> setDriverStatus(String driverId, String status) async {
    await _send('PATCH', '/api/drivers/$driverId/status', body: {'status': status}, fallback: 'Unable to update this driver');
  }

  /// Approve/reject a document. [rejectionReason] is required by the
  /// backend when [status] is REJECTED — omitting it there is rejected as
  /// a 400, never silently accepted as a bare "Rejected" with no reason.
  Future<void> reviewDocument(String documentId, {required String status, String? rejectionReason}) async {
    await _send(
      'PATCH',
      '/api/documents/$documentId/review',
      body: {'status': status, if (rejectionReason != null) 'rejectionReason': rejectionReason},
      fallback: 'Unable to review this document',
    );
  }

  /// Approve/reject a vehicle. [reason] is required by the backend when
  /// [status] is REJECTED.
  Future<void> reviewVehicle(String vehicleId, {required String status, String? reason}) async {
    await _send(
      'PATCH',
      '/api/vehicles/$vehicleId/review',
      body: {'status': status, if (reason != null) 'reason': reason},
      fallback: 'Unable to review this vehicle',
    );
  }

  Future<String> fetchDocumentViewUrl(String documentId) async {
    final res = await _send('GET', '/api/documents/$documentId/view', fallback: 'Unable to open this document');
    return (jsonDecode(res.body) as Map<String, dynamic>)['viewUrl'] as String;
  }
}
