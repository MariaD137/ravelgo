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
  });

  /// The amount actually owed: the final fare once set, otherwise the estimate.
  double get fare => finalFare ?? estimatedFare;

  static double _toDouble(dynamic v) =>
      v == null ? 0 : (v is num ? v.toDouble() : double.tryParse('$v') ?? 0);

  static DateTime _toDate(dynamic v) =>
      v == null ? DateTime.now() : (DateTime.tryParse('$v')?.toLocal() ?? DateTime.now());

  factory Trip.fromJson(Map<String, dynamic> j) {
    String? driverName;
    final driver = j['driver'];
    if (driver is Map && driver['user'] is Map) {
      final u = driver['user'] as Map;
      driverName = [u['firstName'], u['lastName']]
          .where((e) => e != null && '$e'.trim().isNotEmpty)
          .join(' ')
          .trim();
      if (driverName.isEmpty) driverName = null;
    }
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
}
