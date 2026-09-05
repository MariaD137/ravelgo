import 'package:http/http.dart' as http;
import 'package:ravelgo_driver_app/services/api_client.dart';
import 'package:ravelgo_driver_app/services/auth_service.dart';

/// The driver's backend record (GET /api/drivers/me). Name/email live on the
/// Cognito profile, not this row, so they come from AuthService.
class DriverRecord {
  final String id;
  final String status; // PENDING_REVIEW | ACTIVE | SUSPENDED
  final bool isOnline;
  final double rating;
  final int totalTrips;
  final String preferredLanguage;

  DriverRecord({
    required this.id,
    required this.status,
    required this.isOnline,
    required this.rating,
    required this.totalTrips,
    required this.preferredLanguage,
  });

  bool get isApproved => status == 'ACTIVE';

  factory DriverRecord.fromJson(Map<String, dynamic> j) => DriverRecord(
        id: '${j['id']}',
        status: '${j['status'] ?? 'PENDING_REVIEW'}',
        isOnline: j['isOnline'] == true,
        rating: (j['rating'] is num) ? (j['rating'] as num).toDouble() : 5.0,
        totalTrips: (j['totalTrips'] is num) ? (j['totalTrips'] as num).toInt() : 0,
        preferredLanguage: '${j['preferredLanguage'] ?? 'English'}',
      );
}

/// A trip from the driver's perspective (GET /api/trips/mine). All fields come
/// from the backend's safe trip serialization — the driver never sees the
/// rider's email/phone/Cognito sub.
class DriverTrip {
  final String id;
  final String pickup;
  final String destination;
  final double estimatedFare;
  final double? finalFare;
  final String status;
  final DateTime requestedAt;
  final String? riderName;
  final double? distanceKm;
  final double? riderRating;
  final String? pickupNote;

  DriverTrip({
    required this.id,
    required this.pickup,
    required this.destination,
    required this.estimatedFare,
    required this.finalFare,
    required this.status,
    required this.requestedAt,
    required this.riderName,
    this.distanceKm,
    this.riderRating,
    this.pickupNote,
  });

  double get fare => finalFare ?? estimatedFare;

  static double _d(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

  factory DriverTrip.fromJson(Map<String, dynamic> j) {
    String? riderName;
    final rider = j['rider'];
    if (rider is Map) {
      riderName = [rider['firstName'], rider['lastName']]
          .where((e) => e != null && '$e'.trim().isNotEmpty)
          .join(' ')
          .trim();
      if (riderName.isEmpty) riderName = null;
    }
    return DriverTrip(
      id: '${j['id']}',
      pickup: '${j['pickup'] ?? ''}',
      destination: '${j['destination'] ?? ''}',
      estimatedFare: _d(j['estimatedFare']),
      finalFare: j['finalFare'] == null ? null : _d(j['finalFare']),
      status: '${j['status'] ?? ''}',
      requestedAt: DateTime.tryParse('${j['requestedAt']}')?.toLocal() ?? DateTime.now(),
      riderName: riderName,
      distanceKm: j['distanceKm'] == null ? null : _d(j['distanceKm']),
      riderRating: j['riderRating'] == null ? null : _d(j['riderRating']),
      pickupNote: (j['pickupNote'] == null || '${j['pickupNote']}'.isEmpty) ? null : '${j['pickupNote']}',
    );
  }
}

class Payout {
  final String id;
  final String status;
  final double amount;
  final String period;
  final DateTime createdAt;

  Payout({
    required this.id,
    required this.status,
    required this.amount,
    required this.period,
    required this.createdAt,
  });

  factory Payout.fromJson(Map<String, dynamic> j) => Payout(
        id: '${j['id']}',
        status: '${j['status'] ?? ''}',
        amount: (j['amount'] is num) ? (j['amount'] as num).toDouble() : double.tryParse('${j['amount']}') ?? 0,
        period: '${j['period'] ?? ''}',
        createdAt: DateTime.tryParse('${j['createdAt']}')?.toLocal() ?? DateTime.now(),
      );
}

class DriverDocument {
  final String id;
  final String title;
  final String status; // NOT_UPLOADED | PENDING | APPROVED | EXPIRING_SOON | REJECTED
  final DateTime? expiryDate;

  DriverDocument({required this.id, required this.title, required this.status, required this.expiryDate});

  factory DriverDocument.fromJson(Map<String, dynamic> j) => DriverDocument(
        id: '${j['id']}',
        title: '${j['title'] ?? ''}',
        status: '${j['status'] ?? 'NOT_UPLOADED'}',
        expiryDate: j['expiryDate'] == null ? null : DateTime.tryParse('${j['expiryDate']}'),
      );
}

/// A package delivery request, from the driver's perspective.
class CourierRequest {
  final String id;
  final String pickupAddress;
  final String dropoffAddress;
  final String packageDescription;
  final String recipientName;
  final String recipientPhone;
  final double estimatedFare;
  final double? finalFare;
  final String status; // REQUESTED | MATCHED | IN_TRANSIT | DELIVERED | CANCELLED
  final DateTime requestedAt;

  CourierRequest({
    required this.id,
    required this.pickupAddress,
    required this.dropoffAddress,
    required this.packageDescription,
    required this.recipientName,
    required this.recipientPhone,
    required this.estimatedFare,
    required this.finalFare,
    required this.status,
    required this.requestedAt,
  });

  static double _d(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

  factory CourierRequest.fromJson(Map<String, dynamic> j) => CourierRequest(
        id: '${j['id']}',
        pickupAddress: '${j['pickupAddress'] ?? ''}',
        dropoffAddress: '${j['dropoffAddress'] ?? ''}',
        packageDescription: '${j['packageDescription'] ?? ''}',
        recipientName: '${j['recipientName'] ?? ''}',
        recipientPhone: '${j['recipientPhone'] ?? ''}',
        estimatedFare: _d(j['estimatedFare']),
        finalFare: j['finalFare'] == null ? null : _d(j['finalFare']),
        status: '${j['status'] ?? ''}',
        requestedAt: DateTime.tryParse('${j['requestedAt']}')?.toLocal() ?? DateTime.now(),
      );
}

class Vehicle {
  final String id;
  final String label;
  final String plateNumber;
  final bool isPrimary;
  Vehicle({required this.id, required this.label, required this.plateNumber, required this.isPrimary});
  factory Vehicle.fromJson(Map<String, dynamic> j) => Vehicle(
        id: '${j['id']}',
        label: '${j['brand'] ?? ''} ${j['model'] ?? ''}'.trim(),
        plateNumber: '${j['plateNumber'] ?? ''}',
        isPrimary: j['isPrimary'] == true,
      );
}

class DriverApi {
  /// Apply to become a driver (safe to call after sign-in; idempotent).
  ///
  /// Uses the server-authoritative onboarding endpoint (POST /api/drivers/apply)
  /// — the backend both creates the PENDING_REVIEW profile and grants the
  /// "Driver" Cognito group with its own IAM role (P0 #2). A fresh sign-up is
  /// only in the "Rider" group, so this is the path that actually elevates the
  /// role; calling /drivers/me instead would 403 for a user who hasn't been
  /// granted the group yet. The client never assigns its own role.
  static Future<void> provisionMe() async {
    final email = AuthService.email;
    if (email == null || email.isEmpty) return;
    await ApiClient.post('/api/drivers/apply', {
      'firstName': (AuthService.givenName?.isNotEmpty ?? false) ? AuthService.givenName : 'Driver',
      'lastName': (AuthService.familyName?.isNotEmpty ?? false) ? AuthService.familyName : 'User',
      'email': email,
    });
  }

  /// The signed-in driver's backend record.
  static Future<DriverRecord> getMe() async {
    final data = await ApiClient.get('/api/drivers/me');
    return DriverRecord.fromJson(data as Map<String, dynamic>);
  }

  /// Go online / offline. Only an ACTIVE (approved) driver can go online.
  static Future<DriverRecord> setOnline(bool online) async {
    final data = await ApiClient.patch('/api/drivers/me/availability', {'isOnline': online});
    return DriverRecord.fromJson(data as Map<String, dynamic>);
  }

  /// Trips assigned to this driver, newest first.
  static Future<List<DriverTrip>> myTrips() async {
    final data = await ApiClient.get('/api/trips/mine?pageSize=50');
    final list = (data is Map ? data['data'] : data) as List? ?? const [];
    return list.whereType<Map<String, dynamic>>().map(DriverTrip.fromJson).toList();
  }

  /// Advance a trip's status (start a matched trip, complete an in-progress one).
  static Future<DriverTrip> updateTripStatus(String tripId, String status, {double? finalFare}) async {
    final data = await ApiClient.patch('/api/trips/$tripId/status', {
      'status': status,
      if (finalFare != null) 'finalFare': finalFare,
    });
    return DriverTrip.fromJson(data as Map<String, dynamic>);
  }

  /// Upload a document: presign an S3 key, PUT the bytes straight to S3, then
  /// record the metadata. Returns the created (PENDING) document.
  static Future<DriverDocument> uploadDocument({
    required String title,
    required String fileName,
    required String contentType,
    required List<int> bytes,
  }) async {
    // 1. Ask the backend for a short-lived presigned PUT URL + object key.
    final presign = await ApiClient.post('/api/uploads/presign', {
      'bucket': 'documents',
      'fileName': fileName,
      'contentType': contentType,
    }) as Map<String, dynamic>;
    final uploadUrl = '${presign['uploadUrl']}';
    final fileKey = '${presign['fileKey']}';

    // 2. PUT the bytes straight to S3 (no auth header — the URL is signed).
    final put = await http.put(Uri.parse(uploadUrl), headers: {'Content-Type': contentType}, body: bytes);
    if (put.statusCode < 200 || put.statusCode >= 300) {
      throw ApiException(put.statusCode, 'File upload failed (${put.statusCode}).');
    }

    // 3. Record the document against the driver.
    final doc = await ApiClient.post('/api/documents', {'title': title, 'fileKey': fileKey}) as Map<String, dynamic>;
    return DriverDocument.fromJson(doc);
  }

  /// The driver's uploaded documents and their approval status.
  static Future<List<DriverDocument>> myDocuments() async {
    final data = await ApiClient.get('/api/documents/me');
    final list = data as List? ?? const [];
    return list.whereType<Map<String, dynamic>>().map(DriverDocument.fromJson).toList();
  }

  /// Raise an emergency SOS alert (reaches the admin safety queue).
  static Future<void> raiseSos({String? message}) async {
    await ApiClient.post('/api/emergency-alerts', {
      'type': 'SOS',
      if (message != null && message.isNotEmpty) 'message': message,
    });
  }

  /// Report suspected fraud / suspicious activity (reaches the admin queue).
  static Future<void> reportFraud({String? message}) async {
    await ApiClient.post('/api/emergency-alerts', {
      'type': 'FRAUD_SUSPECTED',
      if (message != null && message.isNotEmpty) 'message': message,
    });
  }

  /// Submit a Car Paddy (vehicle papers renewal) request for a plate.
  static Future<void> submitCarPaddy(String plateNumber) async {
    await ApiClient.post('/api/car-paddy', {'plateNumber': plateNumber});
  }

  /// The driver's vehicles.
  static Future<List<Vehicle>> myVehicles() async {
    final data = await ApiClient.get('/api/vehicles/me');
    final list = data as List? ?? const [];
    return list.whereType<Map<String, dynamic>>().map(Vehicle.fromJson).toList();
  }

  /// List one of the driver's vehicles for luxury rental.
  static Future<void> listForRental({
    required String vehicleId,
    required double dailyRate,
    required String location,
  }) async {
    await ApiClient.post('/api/rentals', {
      'vehicleId': vehicleId,
      'dailyRate': dailyRate,
      'location': location,
    });
  }

  /// The driver's saved payout bank account, or null if none set.
  static Future<Map<String, dynamic>?> bankAccount() async {
    try {
      final data = await ApiClient.get('/api/payouts/bank-account');
      return data is Map<String, dynamic> ? data : null;
    } on ApiException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  /// Save / update the driver's payout bank account.
  static Future<void> saveBankAccount({
    required String accountHolderName,
    required String bankName,
    required String accountNumber,
    required String routingNumber,
  }) async {
    await ApiClient.post('/api/payouts/bank-account', {
      'accountHolderName': accountHolderName,
      'bankName': bankName,
      'accountNumber': accountNumber,
      'routingNumber': routingNumber,
    });
  }

  /// The driver's payout history (earnings paid out).
  static Future<List<Payout>> payoutHistory() async {
    final data = await ApiClient.get('/api/payouts/history');
    final list = (data is Map ? (data['data'] ?? data['payouts']) : data) as List? ?? const [];
    return list.whereType<Map<String, dynamic>>().map(Payout.fromJson).toList();
  }

  /// Unassigned delivery requests available to accept. Only an ACTIVE
  /// (admin-approved) driver may call this — a PENDING_REVIEW driver gets a
  /// 409, the same approval gate ride matching uses.
  static Future<List<CourierRequest>> availableDeliveries() async {
    final data = await ApiClient.get('/api/courier-requests/available?pageSize=50');
    final list = (data is Map ? data['data'] : data) as List? ?? const [];
    return list.whereType<Map<String, dynamic>>().map(CourierRequest.fromJson).toList();
  }

  /// Deliveries already accepted by this driver.
  static Future<List<CourierRequest>> myDeliveries() async {
    final data = await ApiClient.get('/api/courier-requests/mine?pageSize=50');
    final list = (data is Map ? data['data'] : data) as List? ?? const [];
    return list.whereType<Map<String, dynamic>>().map(CourierRequest.fromJson).toList();
  }

  /// Accept an available delivery request.
  static Future<CourierRequest> acceptDelivery(String id) async {
    final data = await ApiClient.patch('/api/courier-requests/$id/accept');
    return CourierRequest.fromJson(data as Map<String, dynamic>);
  }

  /// Advance an accepted delivery (picked up -> in transit, dropped off -> delivered).
  static Future<CourierRequest> updateDeliveryStatus(String id, String status, {double? finalFare}) async {
    final data = await ApiClient.patch('/api/courier-requests/$id/status', {
      'status': status,
      if (finalFare != null) 'finalFare': finalFare,
    });
    return CourierRequest.fromJson(data as Map<String, dynamic>);
  }
}
