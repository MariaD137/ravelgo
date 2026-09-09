import 'package:ravelgo_user_app/services/api_client.dart';

double _d(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

/// One vehicle class's rate-card-backed delivery quote (GET
/// /api/pricing/delivery-quote) — one per active DeliveryVehicleRate
/// (Bike/Car/SUV/Van today). Replaces the old hardcoded client-side flat
/// packageSize table; every figure here is the backend's real computation.
class DeliveryVehicleQuote {
  final String vehicleClass; // BIKE | CAR | SUV | VAN
  final String name;
  final double estimatedFare;
  final double initialFee;
  final double distanceFee;
  final double packageSurcharge;
  final double commissionRate;

  DeliveryVehicleQuote({
    required this.vehicleClass,
    required this.name,
    required this.estimatedFare,
    required this.initialFee,
    required this.distanceFee,
    required this.packageSurcharge,
    required this.commissionRate,
  });

  factory DeliveryVehicleQuote.fromJson(Map<String, dynamic> j) => DeliveryVehicleQuote(
        vehicleClass: '${j['vehicleClass'] ?? ''}',
        name: '${j['name'] ?? ''}',
        estimatedFare: _d(j['estimatedFare']),
        initialFee: _d(j['initialFee']),
        distanceFee: _d(j['distanceFee']),
        packageSurcharge: _d(j['packageSurcharge']),
        commissionRate: _d(j['commissionRate']),
      );
}

/// A package delivery request, from the sending customer's perspective. The
/// price (estimatedFare) is always computed server-side from packageSize —
/// this client never asserts a price.
class CourierRequest {
  final String id;
  final String pickupAddress;
  final String dropoffAddress;
  final String packageDescription;
  final String packageSize; // SMALL | MEDIUM | LARGE
  final String recipientName;
  final String recipientPhone;
  final double estimatedFare;
  final double? finalFare;
  final String
  status; // REQUESTED | MATCHED | PICKED_UP | IN_TRANSIT | DELIVERED | CANCELLED
  final DateTime requestedAt;
  final DateTime? pickedUpAt;
  final DateTime? deliveredAt;
  // Short-lived, signed GET URLs — present only once a photo/signature has
  // been captured (i.e. once the request reaches DELIVERED).
  final String? deliveryPhotoUrl;
  final String? recipientSignatureUrl;
  // Resolved by the sender's Places-backed address search at request time —
  // null for a request made before this existed, or whose address never
  // resolved. Never fabricated.
  final double? pickupLat;
  final double? pickupLng;
  final double? dropoffLat;
  final double? dropoffLng;
  // The courier's CURRENT position — the same real driver GPS feed behind
  // the admin Live Map's Packages view, only present once the assigned
  // driver has reported at least one location. Only present on the
  // single-request detail fetch (GET /courier-requests/:id), not on lists.
  final double? courierLat;
  final double? courierLng;
  final DateTime? courierLocationUpdatedAt;
  final String? courierPresence; // LIVE | STALE | null (no report yet)
  // The vehicle class (BIKE/CAR/SUV/VAN) chosen at request time, when the
  // backend priced this off the real DeliveryVehicleRate rate card — null for
  // a request that fell back to the legacy flat packageSize table.
  final String? deliveryVehicleClass;

  CourierRequest({
    required this.id,
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
    this.deliveryPhotoUrl,
    this.recipientSignatureUrl,
    this.pickupLat,
    this.pickupLng,
    this.dropoffLat,
    this.dropoffLng,
    this.courierLat,
    this.courierLng,
    this.courierLocationUpdatedAt,
    this.courierPresence,
    this.deliveryVehicleClass,
  });

  static double? _dOrNull(dynamic v) => v == null ? null : _d(v);

  factory CourierRequest.fromJson(Map<String, dynamic> j) => CourierRequest(
    id: '${j['id']}',
    pickupAddress: '${j['pickupAddress'] ?? ''}',
    dropoffAddress: '${j['dropoffAddress'] ?? ''}',
    packageDescription: '${j['packageDescription'] ?? ''}',
    packageSize: '${j['packageSize'] ?? 'MEDIUM'}',
    recipientName: '${j['recipientName'] ?? ''}',
    recipientPhone: '${j['recipientPhone'] ?? ''}',
    estimatedFare: _d(j['estimatedFare']),
    finalFare: j['finalFare'] == null ? null : _d(j['finalFare']),
    status: '${j['status'] ?? ''}',
    requestedAt:
        DateTime.tryParse('${j['requestedAt']}')?.toLocal() ?? DateTime.now(),
    pickedUpAt: j['pickedUpAt'] == null
        ? null
        : DateTime.tryParse('${j['pickedUpAt']}')?.toLocal(),
    deliveredAt: j['deliveredAt'] == null
        ? null
        : DateTime.tryParse('${j['deliveredAt']}')?.toLocal(),
    deliveryPhotoUrl: (j['deliveryPhotoUrl'] as String?)?.isNotEmpty == true
        ? j['deliveryPhotoUrl'] as String
        : null,
    recipientSignatureUrl:
        (j['recipientSignatureUrl'] as String?)?.isNotEmpty == true
        ? j['recipientSignatureUrl'] as String
        : null,
    pickupLat: _dOrNull(j['pickupLat']),
    pickupLng: _dOrNull(j['pickupLng']),
    dropoffLat: _dOrNull(j['dropoffLat']),
    dropoffLng: _dOrNull(j['dropoffLng']),
    courierLat: _dOrNull(j['courierLat']),
    courierLng: _dOrNull(j['courierLng']),
    courierLocationUpdatedAt: j['courierLocationUpdatedAt'] == null
        ? null
        : DateTime.tryParse('${j['courierLocationUpdatedAt']}')?.toLocal(),
    courierPresence: j['courierPresence']?.toString(),
    deliveryVehicleClass: (j['deliveryVehicleClass'] as String?)?.isNotEmpty == true
        ? j['deliveryVehicleClass'] as String
        : null,
  );
}

/// Package delivery, proxied through the RavelGo backend. Backed by the same
/// POST /api/courier-requests a driver later browses and accepts.
class CourierApi {
  /// Real per-vehicle-class delivery quotes (GET /api/pricing/delivery-quote)
  /// — one entry per active vehicle class (Bike/Car/SUV/Van today). Requires
  /// a real distance; never call this with a guessed/placeholder one.
  static Future<List<DeliveryVehicleQuote>> quote({
    required double distanceKm,
    required String packageSize,
  }) async {
    final data = await ApiClient.get(
      '/api/pricing/delivery-quote?distanceKm=$distanceKm&packageSize=${Uri.encodeComponent(packageSize)}',
    );
    return ((data as List?) ?? const [])
        .map((e) => DeliveryVehicleQuote.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// [deliveryVehicleClass], when sent together with both pickup/dropoff
  /// coordinate pairs, prices the request off the real DeliveryVehicleRate
  /// rate card + haversine distance instead of the legacy flat packageSize
  /// table — always pass it when a vehicle class and both coordinate pairs
  /// are known.
  static Future<CourierRequest> create({
    required String pickupAddress,
    required String dropoffAddress,
    required String packageDescription,
    required String packageSize,
    required String recipientName,
    required String recipientPhone,
    double? pickupLat,
    double? pickupLng,
    double? dropoffLat,
    double? dropoffLng,
    String? deliveryVehicleClass,
  }) async {
    final data = await ApiClient.post('/api/courier-requests', {
      'pickupAddress': pickupAddress,
      'dropoffAddress': dropoffAddress,
      'packageDescription': packageDescription,
      'packageSize': packageSize,
      'recipientName': recipientName,
      'recipientPhone': recipientPhone,
      if (pickupLat != null) 'pickupLat': pickupLat,
      if (pickupLng != null) 'pickupLng': pickupLng,
      if (dropoffLat != null) 'dropoffLat': dropoffLat,
      if (dropoffLng != null) 'dropoffLng': dropoffLng,
      if (deliveryVehicleClass != null && deliveryVehicleClass.isNotEmpty)
        'deliveryVehicleClass': deliveryVehicleClass,
    });
    return CourierRequest.fromJson(data as Map<String, dynamic>);
  }

  /// Current status of a single delivery request (for tracking).
  static Future<CourierRequest> status(String id) async {
    final data = await ApiClient.get('/api/courier-requests/$id');
    return CourierRequest.fromJson(data as Map<String, dynamic>);
  }

  /// All delivery requests this customer has sent (delivery history).
  static Future<List<CourierRequest>> sent() async {
    final data = await ApiClient.get('/api/courier-requests/sent');
    return ((data as List?) ?? const [])
        .map((e) => CourierRequest.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Cancel a delivery request this customer sent — only possible while the
  /// backend still considers it cancellable (REQUESTED or MATCHED, i.e.
  /// before a driver has physically picked the package up).
  static Future<CourierRequest> cancel(String id) async {
    final data = await ApiClient.post('/api/courier-requests/$id/cancel');
    return CourierRequest.fromJson(data as Map<String, dynamic>);
  }
}
