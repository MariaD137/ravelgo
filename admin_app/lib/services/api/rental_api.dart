import 'api_client.dart';

/// Admin's rental-approval API surface — a RentalListing (a driver's ad for
/// their vehicle) is distinct from a RentalBooking (one renter's
/// reservation against a listing); never imports rider_api.dart,
/// driver_api.dart, or courier_api.dart.
class RentalApi {
  RentalApi(this._client);

  final ApiClient _client;

  /// Admin callers see listings of every status (not just APPROVED) — see
  /// the isAdmin branch in rentals.routes.ts's GET /rentals.
  Future<List<Map<String, dynamic>>> listListings({int page = 1, int pageSize = 20}) async {
    final res = await _client.get('/api/rentals', query: {'page': page, 'pageSize': pageSize})
        as Map<String, dynamic>;
    return (res['data'] as List).cast<Map<String, dynamic>>();
  }

  /// [status] must be APPROVED or REJECTED.
  Future<Map<String, dynamic>> decideListing(String listingId, String status) async {
    return await _client.patch('/api/rentals/$listingId/status', body: {'status': status})
        as Map<String, dynamic>;
  }

  /// The bookings made against one listing.
  Future<List<Map<String, dynamic>>> listBookingsForListing(String listingId) async {
    final res = await _client.get('/api/rentals/$listingId/bookings');
    return (res as List).cast<Map<String, dynamic>>();
  }
}
