import 'api_client.dart';

/// Courier's own API surface for the rider app — never imports ride_api.dart
/// or rental_api.dart, matching the same domain separation kept on the
/// backend and in driver_app's API layer.
class CourierApi {
  CourierApi(this._client);

  final ApiClient _client;

  Future<Map<String, dynamic>> createRequest({
    required String pickupAddress,
    required String dropoffAddress,
    required String packageDescription,
    required String recipientName,
    required String recipientPhone,
    required double estimatedFare,
  }) async {
    return await _client.post(
          '/api/courier-requests',
          body: {
            'pickupAddress': pickupAddress,
            'dropoffAddress': dropoffAddress,
            'packageDescription': packageDescription,
            'recipientName': recipientName,
            'recipientPhone': recipientPhone,
            'estimatedFare': estimatedFare,
          },
        )
        as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getById(String id) async {
    return await _client.get('/api/courier-requests/$id') as Map<String, dynamic>;
  }

  /// The calling sender's own courier request history, most recent first.
  Future<List<Map<String, dynamic>>> myRequests({int page = 1, int pageSize = 20}) async {
    final res = await _client.get('/api/courier-requests/mine', query: {'page': page, 'pageSize': pageSize})
        as Map<String, dynamic>;
    return (res['data'] as List).cast<Map<String, dynamic>>();
  }
}
