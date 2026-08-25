import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:ravelgo_driver_app/models/document_item.dart';
import 'package:ravelgo_driver_app/models/vehicle.dart';
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

/// Internal-only: signals a 401 so _sendWithRetry can refresh and retry
/// once. Never escapes to a caller.
class _NeedsRefreshException implements Exception {}

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
      // fall through to a status-appropriate message below.
    }
    switch (res.statusCode) {
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
        if (res.statusCode >= 500) return 'The server ran into a problem. Please try again shortly.';
        return fallback;
    }
  }

  Future<DriverSummary> fetchSummary() async {
    final res = await _get('/api/drivers/me/summary', fallback: 'Unable to load dashboard');
    return DriverSummary.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// Sets presence on the backend and returns the confirmed state. Throws
  /// [DriverApiException] with the backend's own reason (e.g. pending
  /// review or suspended) if the toggle is rejected — callers must not
  /// flip local UI state until this resolves successfully.
  Future<bool> setOnline(bool isOnline) async {
    final res = await _send(
      'PATCH',
      '/api/drivers/me/online',
      body: {'isOnline': isOnline},
      fallback: 'Unable to update your status',
    );
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    return json['isOnline'] as bool;
  }

  /// Creates this driver's backend profile — called once, right after
  /// sign-up (see backend/src/routes/drivers.routes.ts's own comment).
  /// Requires a real signed-in session same as every other call here; on
  /// this build (no Cognito sign-in wired into the app yet) it will
  /// honestly fail with "You need to sign in again." rather than pretend
  /// to succeed.
  Future<void> createDriverProfile({
    required String firstName,
    required String lastName,
    required String email,
    String? phoneNumber,
    required String preferredLanguage,
    bool quietModePreferred = false,
  }) async {
    await _send(
      'POST',
      '/api/drivers/me',
      body: {
        'firstName': firstName,
        'lastName': lastName,
        'email': email,
        if (phoneNumber != null && phoneNumber.isNotEmpty) 'phoneNumber': phoneNumber,
        'preferredLanguage': preferredLanguage,
        'quietModePreferred': quietModePreferred,
      },
      fallback: 'Unable to save your profile',
      expectedStatus: 201,
    );
  }

  // ---------------------------------------------------------------------
  // Vehicles — backend/src/routes/vehicles.routes.ts. Every call is scoped
  // to the calling driver's own vehicles by the backend (never trust a
  // client-side id check alone).
  // ---------------------------------------------------------------------

  Future<List<Vehicle>> fetchVehicles() async {
    final res = await _get('/api/vehicles/me', fallback: 'Unable to load your vehicles');
    return (jsonDecode(res.body) as List).map((v) => Vehicle.fromJson(v as Map<String, dynamic>)).toList();
  }

  Future<Vehicle> fetchVehicle(String vehicleId) async {
    final res = await _get('/api/vehicles/$vehicleId', fallback: 'Unable to load this vehicle');
    return Vehicle.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<Vehicle> createVehicle({
    required String brand,
    required String model,
    required String colour,
    required String plateNumber,
    required String year,
    String? vin,
    required VehicleType vehicleType,
    bool isPrimary = false,
  }) async {
    final res = await _send(
      'POST',
      '/api/vehicles',
      body: {
        'brand': brand,
        'model': model,
        'colour': colour,
        'plateNumber': plateNumber,
        'year': year,
        if (vin != null && vin.isNotEmpty) 'vin': vin,
        'vehicleType': vehicleTypeToJson(vehicleType),
        'isPrimary': isPrimary,
      },
      fallback: 'Unable to save this vehicle',
      expectedStatus: 201,
    );
    return Vehicle.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<Vehicle> updateVehicle(
    String vehicleId, {
    required String brand,
    required String model,
    required String colour,
    required String plateNumber,
    required String year,
    String? vin,
    required VehicleType vehicleType,
  }) async {
    final res = await _send(
      'PATCH',
      '/api/vehicles/$vehicleId',
      body: {
        'brand': brand,
        'model': model,
        'colour': colour,
        'plateNumber': plateNumber,
        'year': year,
        // Omitted entirely (not sent as JSON null) when empty — the
        // backend's zod schema treats vin as optional-but-absent, not
        // nullable; sending an explicit null fails validation.
        if (vin != null && vin.isNotEmpty) 'vin': vin,
        'vehicleType': vehicleTypeToJson(vehicleType),
      },
      fallback: 'Unable to save your changes',
    );
    return Vehicle.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<Vehicle> deactivateVehicle(String vehicleId) async {
    final res = await _send('PATCH', '/api/vehicles/$vehicleId/deactivate', fallback: 'Unable to remove this vehicle');
    return Vehicle.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<Vehicle> resubmitVehicle(String vehicleId) async {
    final res = await _send('POST', '/api/vehicles/$vehicleId/resubmit', fallback: 'Unable to resubmit this vehicle');
    return Vehicle.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<void> deleteVehiclePhoto(String vehicleId, String photoId) async {
    await _send('DELETE', '/api/vehicles/$vehicleId/photos/$photoId', fallback: 'Unable to remove this photo', expectedStatus: 204);
  }

  /// Full photo upload pipeline: presign -> PUT the bytes straight to S3 ->
  /// register the resulting fileKey against the vehicle. The UI layer only
  /// ever needs to call this one method with picked image bytes.
  Future<VehiclePhoto> uploadVehiclePhoto({
    required String vehicleId,
    required Uint8List bytes,
    required String fileName,
    required String contentType,
    required VehiclePhotoType photoType,
    int displayOrder = 0,
  }) async {
    final presigned = await _presign(bucket: 'assets', fileName: fileName, contentType: contentType, fileSize: bytes.length);
    await _putToS3(presigned['uploadUrl'] as String, bytes, contentType);

    final res = await _send(
      'POST',
      '/api/vehicles/$vehicleId/photos',
      body: {
        'fileKey': presigned['fileKey'],
        'photoType': vehiclePhotoTypeToJson(photoType),
        'displayOrder': displayOrder,
      },
      fallback: 'Unable to save this photo',
      expectedStatus: 201,
    );
    return VehiclePhoto.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  // ---------------------------------------------------------------------
  // Documents — backend/src/routes/documents.routes.ts.
  // ---------------------------------------------------------------------

  Future<List<DriverDocument>> fetchDocuments({String? vehicleId}) async {
    final path = vehicleId == null ? '/api/documents/me' : '/api/documents/me?vehicleId=$vehicleId';
    final res = await _get(path, fallback: 'Unable to load your documents');
    return (jsonDecode(res.body) as List).map((d) => DriverDocument.fromJson(d as Map<String, dynamic>)).toList();
  }

  /// Full document upload pipeline: presign -> PUT to the private documents
  /// bucket -> register the metadata.
  Future<DriverDocument> uploadDocument({
    required Uint8List bytes,
    required String fileName,
    required String contentType,
    required String title,
    required DriverDocumentType documentType,
    String? vehicleId,
    DateTime? expiryDate,
  }) async {
    final presigned = await _presign(bucket: 'documents', fileName: fileName, contentType: contentType, fileSize: bytes.length);
    await _putToS3(presigned['uploadUrl'] as String, bytes, contentType);

    final res = await _send(
      'POST',
      '/api/documents',
      body: {
        'title': title,
        'fileKey': presigned['fileKey'],
        'documentType': driverDocumentTypeToJson(documentType),
        if (vehicleId != null) 'vehicleId': vehicleId,
        if (expiryDate != null) 'expiryDate': expiryDate.toIso8601String(),
      },
      fallback: 'Unable to upload this document',
      expectedStatus: 201,
    );
    return DriverDocument.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// Replaces a rejected document's file and resends it for review.
  Future<DriverDocument> resubmitDocument({
    required String documentId,
    required Uint8List bytes,
    required String fileName,
    required String contentType,
  }) async {
    final presigned = await _presign(bucket: 'documents', fileName: fileName, contentType: contentType, fileSize: bytes.length);
    await _putToS3(presigned['uploadUrl'] as String, bytes, contentType);

    final res = await _send(
      'POST',
      '/api/documents/$documentId/resubmit',
      body: {'fileKey': presigned['fileKey']},
      fallback: 'Unable to resubmit this document',
    );
    return DriverDocument.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// A short-lived URL to view a document's actual file (opens in the
  /// device's default viewer/browser — see url_launcher usage in the UI).
  Future<String> fetchDocumentViewUrl(String documentId) async {
    final res = await _get('/api/documents/$documentId/view', fallback: 'Unable to open this document');
    return (jsonDecode(res.body) as Map<String, dynamic>)['viewUrl'] as String;
  }

  // ---------------------------------------------------------------------
  // Shared HTTP + upload plumbing
  // ---------------------------------------------------------------------

  Future<Map<String, dynamic>> _presign({
    required String bucket,
    required String fileName,
    required String contentType,
    required int fileSize,
  }) async {
    final res = await _send(
      'POST',
      '/api/uploads/presign',
      body: {'bucket': bucket, 'fileName': fileName, 'contentType': contentType, 'fileSize': fileSize},
      fallback: 'Unable to prepare this upload',
    );
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// PUTs raw bytes straight to S3 using the presigned URL — never goes
  /// through this app's own backend, and never carries an Authorization
  /// header (the URL's signature is the only credential S3 checks), so
  /// there's no 401/refresh path here — only a timeout/network guard.
  Future<void> _putToS3(String uploadUrl, Uint8List bytes, String contentType) async {
    final http.Response res;
    try {
      res = await _client
          .put(Uri.parse(uploadUrl), headers: {'Content-Type': contentType}, body: bytes)
          .timeout(_timeout);
    } on TimeoutException {
      throw const DriverApiException('Upload timed out — check your connection and try again');
    } catch (_) {
      throw const DriverApiException('Upload failed — check your connection and try again');
    }
    if (res.statusCode != 200) {
      throw const DriverApiException('Upload failed — check your connection and try again');
    }
  }

  Future<http.Response> _get(String path, {required String fallback}) => _send('GET', path, fallback: fallback);

  static const _timeout = Duration(seconds: 15);

  /// One request+response attempt, scoped to the token available at call
  /// time. Throws _NeedsRefreshException on a 401 instead of surfacing it
  /// directly — see _send below, which is what callers actually use.
  Future<http.Response> _attempt(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final uri = Uri.parse('$baseUrl$path');
    final headers = await _authHeaders();
    final http.Response res;
    switch (method) {
      case 'GET':
        res = await _client.get(uri, headers: headers).timeout(_timeout);
        break;
      case 'POST':
        res = await _client.post(uri, headers: headers, body: body == null ? null : jsonEncode(body)).timeout(_timeout);
        break;
      case 'PATCH':
        res = await _client.patch(uri, headers: headers, body: body == null ? null : jsonEncode(body)).timeout(_timeout);
        break;
      case 'DELETE':
        res = await _client.delete(uri, headers: headers).timeout(_timeout);
        break;
      default:
        throw ArgumentError('Unsupported method $method');
    }
    if (res.statusCode == 401) throw _NeedsRefreshException();
    return res;
  }

  /// Runs one request, and on a 401 refreshes the session via
  /// [authTokenProvider] and retries exactly once with the refreshed
  /// token — never more than that. If refresh fails (or the retry is
  /// still a 401), clears the session so the app stops presenting itself
  /// as signed in with a token the backend will only ever reject.
  Future<http.Response> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    required String fallback,
    int expectedStatus = 200,
  }) async {
    http.Response res;
    try {
      try {
        res = await _attempt(method, path, body: body);
      } on _NeedsRefreshException {
        final refreshed = await authTokenProvider.refreshAccessToken();
        if (!refreshed) {
          await authTokenProvider.clearSession();
          throw const DriverApiException('Your session has expired. Please sign in again.');
        }
        try {
          res = await _attempt(method, path, body: body);
        } on _NeedsRefreshException {
          await authTokenProvider.clearSession();
          throw const DriverApiException('Your session has expired. Please sign in again.');
        }
      }
    } on DriverApiException {
      rethrow;
    } on TimeoutException {
      throw const DriverApiException('The request timed out. Please try again.');
    } catch (_) {
      throw DriverApiException(fallback);
    }

    if (res.statusCode != expectedStatus) {
      throw DriverApiException(_errorMessage(res, fallback));
    }
    return res;
  }
}
