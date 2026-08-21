import 'package:ravelgo_driver_app/services/api_client.dart';

class TripService {
  static final TripService _instance = TripService._();
  factory TripService() => _instance;
  TripService._();

  final _api = ApiClient();

  Future<Map<String, dynamic>> getTrip(String tripId) async {
    final response = await _api.get('/trips/$tripId');
    return Map<String, dynamic>.from(response);
  }

  Future<Map<String, dynamic>> acceptTrip(String tripId) async {
    final response = await _api.patch('/trips/$tripId/status', body: {'status': 'IN_PROGRESS'});
    return Map<String, dynamic>.from(response);
  }

  Future<Map<String, dynamic>> completeTrip(String tripId, double finalFare) async {
    final response = await _api.patch('/trips/$tripId/status', body: {
      'status': 'COMPLETED',
      'finalFare': finalFare,
    });
    return Map<String, dynamic>.from(response);
  }

  Future<Map<String, dynamic>> cancelTrip(String tripId) async {
    final response = await _api.patch('/trips/$tripId/status', body: {'status': 'CANCELLED'});
    return Map<String, dynamic>.from(response);
  }

  Future<Map<String, dynamic>> chargeTrip(String tripId, {String method = 'CARD'}) async {
    final response = await _api.post('/trips/$tripId/charge', body: {'method': method});
    return Map<String, dynamic>.from(response);
  }
}
