import 'package:ravelgo_user/services/api_client.dart';

class TripService {
  static final TripService _instance = TripService._();
  factory TripService() => _instance;
  TripService._();

  final _api = ApiClient();

  Future<Map<String, dynamic>> requestTrip({
    required String pickup,
    required String destination,
    required double estimatedFare,
    String category = 'Personal',
    String? pickupNote,
  }) async {
    final body = <String, dynamic>{
      'pickup': pickup,
      'destination': destination,
      'estimatedFare': estimatedFare,
      'category': category,
    };
    if (pickupNote != null) body['pickupNote'] = pickupNote;
    final response = await _api.post('/trips', body: body);
    return Map<String, dynamic>.from(response);
  }

  Future<Map<String, dynamic>> getTrip(String tripId) async {
    final response = await _api.get('/trips/$tripId');
    return Map<String, dynamic>.from(response);
  }

  Future<Map<String, dynamic>> cancelTrip(String tripId) async {
    final response = await _api.patch('/trips/$tripId/status', body: {'status': 'CANCELLED'});
    return Map<String, dynamic>.from(response);
  }

  Future<Map<String, dynamic>?> getDriverLocation(String tripId) async {
    try {
      final response = await _api.get('/trips/$tripId/driver-location');
      return Map<String, dynamic>.from(response);
    } on ApiException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }
}
