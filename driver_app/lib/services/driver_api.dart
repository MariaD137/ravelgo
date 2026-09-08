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
  // Resolved by the rider's Places-backed address search at request time —
  // null for a trip whose address never resolved. Never fabricated.
  final double? pickupLat;
  final double? pickupLng;
  final double? dropoffLat;
  final double? dropoffLng;

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
    this.pickupLat,
    this.pickupLng,
    this.dropoffLat,
    this.dropoffLng,
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
      pickupLat: j['pickupLat'] == null ? null : _d(j['pickupLat']),
      pickupLng: j['pickupLng'] == null ? null : _d(j['pickupLng']),
      dropoffLat: j['dropoffLat'] == null ? null : _d(j['dropoffLat']),
      dropoffLng: j['dropoffLng'] == null ? null : _d(j['dropoffLng']),
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

/// A package delivery request, from the driver's perspective. All fields come
/// from the backend's safe courier serialization (serializeCourierRequest) —
/// the driver never sees the customer's email/phone/Cognito sub, only what
/// this shape exposes.
class CourierRequest {
  final String id;
  final String? driverId;
  final String pickupAddress;
  final String dropoffAddress;
  final String packageDescription;
  final String packageSize; // SMALL | MEDIUM | LARGE
  final String recipientName;
  final String recipientPhone;
  final double estimatedFare;
  final double? finalFare;
  final String status; // REQUESTED | MATCHED | PICKED_UP | IN_TRANSIT | DELIVERED | CANCELLED
  final DateTime requestedAt;
  final DateTime? pickedUpAt;
  final DateTime? deliveredAt;
  final String? senderName;
  final double? distanceKm;
  // Resolved by the sender's address search at request time — null for a
  // request made before this existed, or whose address never resolved.
  final double? pickupLat;
  final double? pickupLng;
  final double? dropoffLat;
  final double? dropoffLng;
  // Signed GET URLs — present only once proof of delivery has been captured.
  final String? deliveryPhotoUrl;
  final String? recipientSignatureUrl;
  // This driver's own current position on this job — the same real GPS feed
  // behind the admin Live Map's Packages view, reported via [DriverApi.
  // pingLocation]/the trip-room WebSocket. Never a second tracking system,
  // never fabricated. Only present on the single-request detail fetch.
  final double? courierLat;
  final double? courierLng;
  final DateTime? courierLocationUpdatedAt;
  final String? courierPresence; // LIVE | STALE | null (no report yet)

  CourierRequest({
    required this.id,
    this.driverId,
    required this.pickupAddress,
    required this.dropoffAddress,
    required this.packageDescription,
    required this.packageSize,
    required this.recipientName,
    required this.recipientPhone,
    required this.estimatedFare,
    required this.finalFare,
    required this.status,
    required this.requestedAt,
    this.pickedUpAt,
    this.deliveredAt,
    this.senderName,
    this.distanceKm,
    this.pickupLat,
    this.pickupLng,
    this.dropoffLat,
    this.dropoffLng,
    this.deliveryPhotoUrl,
    this.recipientSignatureUrl,
    this.courierLat,
    this.courierLng,
    this.courierLocationUpdatedAt,
    this.courierPresence,
  });

  static double _d(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
  static double? _dOrNull(dynamic v) => v == null ? null : _d(v);

  factory CourierRequest.fromJson(Map<String, dynamic> j) {
    String? senderName;
    final sender = j['sender'];
    if (sender is Map) {
      senderName = [sender['firstName'], sender['lastName']]
          .where((e) => e != null && '$e'.trim().isNotEmpty)
          .join(' ')
          .trim();
      if (senderName.isEmpty) senderName = null;
    }
    return CourierRequest(
      id: '${j['id']}',
      driverId: j['driverId'] as String?,
      pickupAddress: '${j['pickupAddress'] ?? ''}',
      dropoffAddress: '${j['dropoffAddress'] ?? ''}',
      packageDescription: '${j['packageDescription'] ?? ''}',
      packageSize: '${j['packageSize'] ?? 'MEDIUM'}',
      recipientName: '${j['recipientName'] ?? ''}',
      recipientPhone: '${j['recipientPhone'] ?? ''}',
      estimatedFare: _d(j['estimatedFare']),
      finalFare: j['finalFare'] == null ? null : _d(j['finalFare']),
      status: '${j['status'] ?? ''}',
      requestedAt: DateTime.tryParse('${j['requestedAt']}')?.toLocal() ?? DateTime.now(),
      pickedUpAt: j['pickedUpAt'] == null ? null : DateTime.tryParse('${j['pickedUpAt']}')?.toLocal(),
      deliveredAt: j['deliveredAt'] == null ? null : DateTime.tryParse('${j['deliveredAt']}')?.toLocal(),
      senderName: senderName,
      distanceKm: _dOrNull(j['distanceKm']),
      pickupLat: _dOrNull(j['pickupLat']),
      pickupLng: _dOrNull(j['pickupLng']),
      dropoffLat: _dOrNull(j['dropoffLat']),
      dropoffLng: _dOrNull(j['dropoffLng']),
      deliveryPhotoUrl: (j['deliveryPhotoUrl'] as String?)?.isNotEmpty == true ? j['deliveryPhotoUrl'] as String : null,
      recipientSignatureUrl:
          (j['recipientSignatureUrl'] as String?)?.isNotEmpty == true ? j['recipientSignatureUrl'] as String : null,
      courierLat: _dOrNull(j['courierLat']),
      courierLng: _dOrNull(j['courierLng']),
      courierLocationUpdatedAt:
          j['courierLocationUpdatedAt'] == null ? null : DateTime.tryParse('${j['courierLocationUpdatedAt']}')?.toLocal(),
      courierPresence: j['courierPresence']?.toString(),
    );
  }
}

/// A driver's vehicle. This is the single model both the vehicle-management
/// screen and the rental-listing flow use — there is no separate local
/// vehicle list anymore.
class Vehicle {
  final String id;
  final String brand;
  final String model;
  final String colour;
  final String plateNumber;
  final String year;
  final bool isPrimary;
  final bool listedForRental;
  // A signed-nothing, publicly viewable CDN URL (the backend serves this
  // from the assets bucket) — never a raw S3 key, and null until a photo has
  // actually been uploaded for this vehicle.
  final String? photoUrl;

  Vehicle({
    required this.id,
    required this.brand,
    required this.model,
    required this.colour,
    required this.plateNumber,
    required this.year,
    required this.isPrimary,
    required this.listedForRental,
    this.photoUrl,
  });

  String get label => '$brand $model'.trim();

  factory Vehicle.fromJson(Map<String, dynamic> j) => Vehicle(
        id: '${j['id']}',
        brand: '${j['brand'] ?? ''}',
        model: '${j['model'] ?? ''}',
        colour: '${j['colour'] ?? ''}',
        plateNumber: '${j['plateNumber'] ?? ''}',
        year: '${j['year'] ?? ''}',
        isPrimary: j['isPrimary'] == true,
        listedForRental: j['listedForRental'] == true,
        photoUrl: (j['photoUrl'] as String?)?.isNotEmpty == true ? j['photoUrl'] as String : null,
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

  /// Report the driver's current position while online. This is what backs
  /// the admin Live Map for a driver who is available/idle rather than
  /// mid-trip — the WebSocket location feed (RealtimeService) only runs while
  /// a trip screen is open. Best-effort: a failed ping shouldn't interrupt
  /// the driver's shift, so callers should swallow errors from this.
  static Future<void> pingLocation(double lat, double lng) async {
    await ApiClient.post('/api/drivers/me/location', {'lat': lat, 'lng': lng});
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

  /// Presign an S3 key (documents bucket by default; pass bucket: 'assets'
  /// for something meant to be publicly viewable, like a vehicle photo) and
  /// PUT the bytes straight to S3. Returns the object key — the caller
  /// decides what to do with it (e.g. record it against a DriverDocument,
  /// a Vehicle's photo, or courier-request proof of delivery). No auth
  /// header on the PUT itself; the URL is signed. fileSize is sent so the
  /// backend can reject an oversized upload before ever signing a URL for
  /// it, and the presigned URL then locks in that exact byte count — S3
  /// itself rejects a PUT whose Content-Length doesn't match.
  static Future<String> uploadToDocumentsBucket({
    required String fileName,
    required String contentType,
    required List<int> bytes,
    String bucket = 'documents',
  }) async {
    final presign = await ApiClient.post('/api/uploads/presign', {
      'bucket': bucket,
      'fileName': fileName,
      'contentType': contentType,
      'fileSize': bytes.length,
    }) as Map<String, dynamic>;
    final uploadUrl = '${presign['uploadUrl']}';
    final fileKey = '${presign['fileKey']}';

    final put = await http.put(Uri.parse(uploadUrl), headers: {'Content-Type': contentType}, body: bytes);
    if (put.statusCode < 200 || put.statusCode >= 300) {
      throw ApiException(put.statusCode, 'File upload failed (${put.statusCode}).');
    }
    return fileKey;
  }

  /// Upload a document: presign an S3 key, PUT the bytes straight to S3, then
  /// record the metadata. Returns the created (PENDING) document.
  static Future<DriverDocument> uploadDocument({
    required String title,
    required String fileName,
    required String contentType,
    required List<int> bytes,
  }) async {
    final fileKey = await uploadToDocumentsBucket(fileName: fileName, contentType: contentType, bytes: bytes);
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

  /// Add a vehicle owned by the calling driver. photoKey (if given) must be
  /// an S3 key this same caller was just presigned for (uploadToDocumentsBucket
  /// with bucket: 'assets') — the backend rejects one that isn't theirs.
  static Future<Vehicle> addVehicle({
    required String brand,
    required String model,
    required String colour,
    required String plateNumber,
    required String year,
    bool isPrimary = false,
    String? photoKey,
  }) async {
    final data = await ApiClient.post('/api/vehicles', {
      'brand': brand,
      'model': model,
      'colour': colour,
      'plateNumber': plateNumber,
      'year': year,
      'isPrimary': isPrimary,
      if (photoKey != null) 'photoKey': photoKey,
    });
    return Vehicle.fromJson(data as Map<String, dynamic>);
  }

  /// Update one of the calling driver's own vehicles.
  static Future<Vehicle> updateVehicle(
    String id, {
    required String brand,
    required String model,
    required String colour,
    required String plateNumber,
    required String year,
    bool isPrimary = false,
    String? photoKey,
  }) async {
    final data = await ApiClient.patch('/api/vehicles/$id', {
      'brand': brand,
      'model': model,
      'colour': colour,
      'plateNumber': plateNumber,
      'year': year,
      'isPrimary': isPrimary,
      if (photoKey != null) 'photoKey': photoKey,
    });
    return Vehicle.fromJson(data as Map<String, dynamic>);
  }

  /// Delete one of the calling driver's own vehicles. The backend rejects
  /// this (409) while the vehicle is listed for rental.
  static Future<void> deleteVehicle(String id) async {
    await ApiClient.delete('/api/vehicles/$id');
  }

  /// List one of the driver's vehicles for luxury rental. lat/lng come from
  /// the Places-backed location picker (PlaceSearchScreen) when the driver
  /// used it; omitted otherwise rather than guessed.
  static Future<void> listForRental({
    required String vehicleId,
    required double dailyRate,
    required String location,
    double? lat,
    double? lng,
  }) async {
    await ApiClient.post('/api/rentals', {
      'vehicleId': vehicleId,
      'dailyRate': dailyRate,
      'location': location,
      if (lat != null) 'lat': lat,
      if (lng != null) 'lng': lng,
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

  /// Full detail of a single delivery request — Package/Pickup/Drop-off/
  /// Assignment/Earnings sections, plus the courier's live location while
  /// assigned. Authorized for: the assigned driver, an ACTIVE driver
  /// previewing a still-unassigned (REQUESTED) request before accepting it,
  /// or an Admin — enforced backend-side, not just by hiding the button.
  static Future<CourierRequest> deliveryDetail(String id) async {
    final data = await ApiClient.get('/api/courier-requests/$id');
    return CourierRequest.fromJson(data as Map<String, dynamic>);
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

  /// Advance an accepted delivery (matched -> picked up -> in transit ->
  /// delivered). Marking DELIVERED requires both [deliveryPhotoKey] and
  /// [recipientSignatureKey] — the backend rejects the transition without them.
  static Future<CourierRequest> updateDeliveryStatus(
    String id,
    String status, {
    double? finalFare,
    String? deliveryPhotoKey,
    String? recipientSignatureKey,
  }) async {
    final data = await ApiClient.patch('/api/courier-requests/$id/status', {
      'status': status,
      if (finalFare != null) 'finalFare': finalFare,
      if (deliveryPhotoKey != null) 'deliveryPhotoKey': deliveryPhotoKey,
      if (recipientSignatureKey != null) 'recipientSignatureKey': recipientSignatureKey,
    });
    return CourierRequest.fromJson(data as Map<String, dynamic>);
  }
}
