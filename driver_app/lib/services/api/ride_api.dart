import 'api_client.dart';

/// Ride's own API surface. Deliberately does not import courier_api.dart or
/// rental_api.dart — Ride, Courier, and Rental each keep their own domain
/// API classes rather than one shared "everything" service class.
class RideApi {
  RideApi(this._client);

  final ApiClient _client;

  /// The driver's current active assignment — Ride, Courier, or Rental, or
  /// null if free — GET /api/drivers/me/assignment. There is no "browse
  /// available rides" or "accept a ride" endpoint: matching is fully
  /// server-side and synchronous (services/matching.ts on the backend), so
  /// this is how a driver discovers they've been matched at all. Polled
  /// primary; a best-effort WebSocket push (see driver_session.dart)
  /// overlays it for near-instant delivery.
  Future<Map<String, dynamic>?> getMyAssignment() async {
    return await _client.get('/api/drivers/me/assignment') as Map<String, dynamic>?;
  }

  Future<Map<String, dynamic>> getTrip(String tripId) async {
    return await _client.get('/api/trips/$tripId') as Map<String, dynamic>;
  }

  /// The driver's own trip history — GET /api/trips/mine, scoped to this
  /// driver's side of the trip (the same endpoint a rider's own trip
  /// history uses, on the rider side).
  Future<List<Map<String, dynamic>>> getMyTrips({int page = 1, int pageSize = 20}) async {
    final res = await _client.get('/api/trips/mine', query: {'page': page, 'pageSize': pageSize}) as Map<String, dynamic>;
    return (res['data'] as List).cast<Map<String, dynamic>>();
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
