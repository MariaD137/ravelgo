import 'api_client.dart';

/// Rental's own API surface for the rider app — a RentalListing (a
/// driver's ad for their vehicle) is distinct from a RentalBooking (one
/// renter's reservation against a listing for a date range); never imports
/// ride_api.dart or courier_api.dart. No Stripe integration exists yet, so
/// booking payment state on the backend is PaymentIntegrationStatus
/// .NOT_CONFIGURED — this class only surfaces what the backend returns, it
/// does not invent a payment flow.
class RentalApi {
  RentalApi(this._client);

  final ApiClient _client;

  /// Approved rental listings available to book. Admin callers additionally
  /// see non-approved listings (backend-enforced, not filtered here).
  Future<List<Map<String, dynamic>>> browseListings({int page = 1, int pageSize = 20}) async {
    final res = await _client.get('/api/rentals', query: {'page': page, 'pageSize': pageSize})
        as Map<String, dynamic>;
    return (res['data'] as List).cast<Map<String, dynamic>>();
  }

  /// Books an APPROVED listing for [startAt]..[endAt]. Throws [ApiException]
  /// with `code == 'RENTAL_OVERLAP'` (409) if the date range conflicts with
  /// an existing booking on the same listing — see services/rentals.ts.
  Future<Map<String, dynamic>> createBooking({
    required String rentalListingId,
    required DateTime startAt,
    required DateTime endAt,
  }) async {
    return await _client.post(
          '/api/rentals/$rentalListingId/bookings',
          body: {'startAt': startAt.toIso8601String(), 'endAt': endAt.toIso8601String()},
        )
        as Map<String, dynamic>;
  }

  /// The calling renter's own bookings.
  Future<List<Map<String, dynamic>>> myBookings() async {
    final res = await _client.get('/api/rentals/bookings/mine');
    return (res as List).cast<Map<String, dynamic>>();
  }

  /// Throws [ApiException] with statusCode 409 if the booking is no longer
  /// in a cancellable status (REQUESTED or CONFIRMED — see rentals.routes.ts).
  Future<Map<String, dynamic>> cancelBooking(String bookingId) async {
    return await _client.patch('/api/rentals/bookings/$bookingId/cancel') as Map<String, dynamic>;
  }
}
