import 'api_client.dart';

/// Ride's own API surface for the rider app. Deliberately does not import
/// courier_api.dart or rental_api.dart — Ride, Courier, and Rental each
/// keep their own domain API classes rather than one shared "everything"
/// service class (same separation driver_app's API layer already keeps).
class RideApi {
  RideApi(this._client);

  final ApiClient _client;

  /// Requests a trip. Pass distanceKm/durationMinutes (e.g. from the map
  /// SDK's route estimate) so the backend recomputes the authoritative fare
  /// itself instead of trusting a client-supplied estimatedFare — see the
  /// fare-resolution comment on POST /trips in trips.routes.ts. Falls back
  /// to estimatedFare only when distance/duration aren't available.
  Future<Map<String, dynamic>> requestTrip({
    required String pickup,
    required String destination,
    double? distanceKm,
    double? durationMinutes,
    String? zone,
    String category = 'Personal',
    String? pickupNote,
    double? estimatedFare,
  }) async {
    return await _client.post(
          '/api/trips',
          body: {
            'pickup': pickup,
            'destination': destination,
            'category': category,
            if (pickupNote != null) 'pickupNote': pickupNote,
            if (distanceKm != null) 'distanceKm': distanceKm,
            if (durationMinutes != null) 'durationMinutes': durationMinutes,
            if (zone != null) 'zone': zone,
            if (estimatedFare != null) 'estimatedFare': estimatedFare,
          },
        )
        as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getTrip(String tripId) async {
    return await _client.get('/api/trips/$tripId') as Map<String, dynamic>;
  }

  /// Throws [ApiException] with statusCode 409 if the trip is no longer in
  /// a cancellable status (see CANCELLABLE_TRIP_STATUSES in trips.routes.ts).
  Future<Map<String, dynamic>> cancelTrip(String tripId) async {
    return await _client.patch('/api/trips/$tripId/cancel') as Map<String, dynamic>;
  }

  /// The calling rider's own trip history, most recent first.
  Future<List<Map<String, dynamic>>> myTrips({int page = 1, int pageSize = 20}) async {
    final res = await _client.get('/api/trips/mine', query: {'page': page, 'pageSize': pageSize})
        as Map<String, dynamic>;
    return (res['data'] as List).cast<Map<String, dynamic>>();
  }
}
