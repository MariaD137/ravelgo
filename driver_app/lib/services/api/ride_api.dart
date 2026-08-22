import 'api_client.dart';

/// Ride's own API surface. Deliberately does not import courier_api.dart or
/// rental_api.dart — Ride, Courier, and Rental each keep their own domain
/// API classes rather than one shared "everything" service class.
class RideApi {
  RideApi(this._client);

  final ApiClient _client;

  Future<Map<String, dynamic>> getTrip(String tripId) async {
    return await _client.get('/api/trips/$tripId') as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> updateStatus(String tripId, String status, {double? finalFare}) async {
    return await _client.patch(
          '/api/trips/$tripId/status',
          body: {
            'status': status,
            if (finalFare != null) 'finalFare': finalFare,
          },
        )
        as Map<String, dynamic>;
  }
}
