import 'package:ravelgo_user_app/services/api_client.dart';

/// A trip as returned by the backend (`GET /api/trips/mine`, `POST /api/trips`).
class Trip {
  final String id;
  final String pickup;
  final String destination;
  final double estimatedFare;
  final double? finalFare;
  final String status;
  final String category;
  final DateTime requestedAt;
  final DateTime? completedAt;
  final String? driverName;
  final double? driverRating;
  final String? vehicleLabel; // e.g. "Silver Toyota Corolla"
  final String? vehiclePlate;
  final double? distanceKm;
  // Only present when fetched via TripsApi.byId (GET /api/trips/:id) — the
  // "mine" list route deliberately stays minimal. Null rather than a guessed
  // value when the trip hasn't been charged yet.
  final String? paymentId;
  final String? paymentMethod; // CARD | CASH | WALLET
  final String? paymentStatus; // PENDING | SUCCEEDED | FAILED | REFUNDED
  final String? paymentCurrency;
  final double? paymentAmount;
  final DateTime? paidAt;

  Trip({
    required this.id,
    required this.pickup,
    required this.destination,
    required this.estimatedFare,
    required this.finalFare,
    required this.status,
    required this.category,
    required this.requestedAt,
    required this.completedAt,
    required this.driverName,
    this.driverRating,
    this.vehicleLabel,
    this.vehiclePlate,
    this.distanceKm,
    this.paymentId,
    this.paymentMethod,
    this.paymentStatus,
    this.paymentCurrency,
    this.paymentAmount,
    this.paidAt,
  });

  /// The amount actually owed: the final fare once set, otherwise the estimate.
  double get fare => finalFare ?? estimatedFare;

  static double _toDouble(dynamic v) =>
      v == null ? 0 : (v is num ? v.toDouble() : double.tryParse('$v') ?? 0);

  static double? _toDoubleOrNull(dynamic v) => v == null ? null : _toDouble(v);

  static DateTime _toDate(dynamic v) =>
      v == null ? DateTime.now() : (DateTime.tryParse('$v')?.toLocal() ?? DateTime.now());

  static DateTime? _toDateOrNull(dynamic v) => v == null ? null : _toDate(v);

  factory Trip.fromJson(Map<String, dynamic> j) {
    String? driverName;
    double? driverRating;
    String? vehicleLabel;
    String? vehiclePlate;
    final driver = j['driver'];
    if (driver is Map) {
      if (driver['user'] is Map) {
        final u = driver['user'] as Map;
        driverName = [u['firstName'], u['lastName']]
            .where((e) => e != null && '$e'.trim().isNotEmpty)
            .join(' ')
            .trim();
        if (driverName.isEmpty) driverName = null;
      }
      if (driver['rating'] != null) driverRating = _toDouble(driver['rating']);
      final v = driver['vehicle'];
      if (v is Map) {
        vehicleLabel = [v['color'], v['make'], v['model']]
            .where((e) => e != null && '$e'.trim().isNotEmpty)
            .join(' ')
            .trim();
        if (vehicleLabel.isEmpty) vehicleLabel = null;
        vehiclePlate = v['plateNumber']?.toString();
      }
    }
    final payment = j['payment'];
    return Trip(
      id: '${j['id']}',
      pickup: '${j['pickup'] ?? ''}',
      destination: '${j['destination'] ?? ''}',
      estimatedFare: _toDouble(j['estimatedFare']),
      finalFare: j['finalFare'] == null ? null : _toDouble(j['finalFare']),
      status: '${j['status'] ?? ''}',
      category: '${j['category'] ?? 'Personal'}',
      requestedAt: _toDate(j['requestedAt']),
      completedAt: j['completedAt'] == null ? null : _toDate(j['completedAt']),
      driverName: driverName,
      driverRating: driverRating,
      vehicleLabel: vehicleLabel,
      vehiclePlate: vehiclePlate,
      distanceKm: _toDoubleOrNull(j['distanceKm']),
      paymentId: payment is Map ? payment['id']?.toString() : null,
      paymentMethod: payment is Map ? payment['method']?.toString() : null,
      paymentStatus: payment is Map ? payment['status']?.toString() : null,
      paymentCurrency: payment is Map ? payment['currency']?.toString() : null,
      paymentAmount: payment is Map ? _toDoubleOrNull(payment['amount']) : null,
      paidAt: payment is Map ? _toDateOrNull(payment['paidAt']) : null,
    );
  }
}

class TripsApi {
  /// Rate the driver (1–5) for a completed trip.
  static Future<void> rate(String tripId, int rating, {String? comment}) async {
    await ApiClient.post('/api/trips/$tripId/rating', {
      'rating': rating,
      if (comment != null && comment.isNotEmpty) 'comment': comment,
    });
  }

  /// The signed-in user's trips (as rider or assigned driver), newest first.
  static Future<List<Trip>> mine({int page = 1, int pageSize = 50}) async {
    final data = await ApiClient.get('/api/trips/mine?page=$page&pageSize=$pageSize');
    final list = (data is Map ? data['data'] : data) as List? ?? const [];
    return list.whereType<Map<String, dynamic>>().map(Trip.fromJson).toList();
  }

  /// Full detail for one trip the caller is party to — the only trip-fetch
  /// that includes real payment data (method/status/amount/paidAt). Used by
  /// the e-receipt screen, which needs authoritative payment info that
  /// [mine] deliberately omits.
  static Future<Trip> byId(String id) async {
    final data = await ApiClient.get('/api/trips/$id');
    return Trip.fromJson(data as Map<String, dynamic>);
  }

  /// Report the rider's current position for this trip — only accepted by
  /// the backend while a driver is assigned or the ride is under way. Backs
  /// the admin Live Map's Riders view; mirrors the driver app's own
  /// location-ping pattern (DriverApi.pingLocation).
  static Future<void> pingLocation(String tripId, double lat, double lng) async {
    await ApiClient.post('/api/trips/$tripId/rider-location', {'lat': lat, 'lng': lng});
  }
}
