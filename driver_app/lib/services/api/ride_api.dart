import 'api_client.dart';

/// Ride's own API surface. Deliberately does not import courier_api.dart or
/// rental_api.dart — Ride, Courier, and Rental each keep their own domain
/// API classes rather than one shared "everything" service class.
class RideApi {
  RideApi(this._client);

  final ApiClient _client;

  /// The driver's current active assignment — Ride, Courier, or Rental, or
  /// null if free — GET /api/drivers/me/assignment. This is a *committed*
  /// job (the driver already accepted it), not a pending offer — used to
  /// detect a job that was already committed before this app session
  /// started tracking (e.g. the app was restarted mid-ride). A brand-new
  /// ride is discovered via [getMyOffer] instead; see driver_session.dart.
  Future<Map<String, dynamic>?> getMyAssignment() async {
    return await _client.get('/api/drivers/me/assignment') as Map<String, dynamic>?;
  }

  /// The driver's own pending ride offer, or null — GET /api/drivers/me/offer.
  /// Real Uber-style dispatch: the backend offers a REQUESTED trip to one
  /// eligible driver at a time; this is how that driver discovers the
  /// offer, before choosing to accept or decline it (see [acceptOffer]/
  /// [declineOffer] below). Polled primary; a best-effort WebSocket push
  /// (see driver_session.dart) overlays it for near-instant delivery.
  Future<Map<String, dynamic>?> getMyOffer() async {
    return await _client.get('/api/drivers/me/offer') as Map<String, dynamic>?;
  }

  /// Accepts a real pending offer — PATCH /api/trip-offers/:id/accept.
  /// Atomic and concurrency-safe server-side: if another driver's accept
  /// (or the offer's own expiry) wins the race first, this throws an
  /// [ApiException] rather than returning a trip. Returns the now-MATCHED
  /// trip on success.
  Future<Map<String, dynamic>> acceptOffer(String offerId) async {
    return await _client.patch('/api/trip-offers/$offerId/accept') as Map<String, dynamic>;
  }

  /// Declines a real pending offer — PATCH /api/trip-offers/:id/decline.
  /// This only resolves this one offer; it never cancels the rider's trip
  /// and never affects the driver's own account status — the backend
  /// keeps the driver available and offers the trip on to the next
  /// eligible driver.
  Future<Map<String, dynamic>> declineOffer(String offerId) async {
    return await _client.patch('/api/trip-offers/$offerId/decline') as Map<String, dynamic>;
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
