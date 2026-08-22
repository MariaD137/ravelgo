import 'api_client.dart';

/// Fare estimation — GET /api/pricing/quote on the backend. Used before a
/// rider requests a trip, so the app can show an estimate and (per
/// trips.routes.ts) pass the same distanceKm/durationMinutes back on
/// POST /trips so the server recomputes the authoritative fare itself.
class PricingApi {
  PricingApi(this._client);

  final ApiClient _client;

  /// Throws [ApiException] with statusCode 409 if no PricingRule is
  /// currently active on the backend.
  Future<Map<String, dynamic>> getQuote({
    required double distanceKm,
    required double durationMinutes,
    String? zone,
  }) async {
    return await _client.get(
          '/api/pricing/quote',
          query: {
            'distanceKm': distanceKm,
            'durationMinutes': durationMinutes,
            if (zone != null) 'zone': zone,
          },
        )
        as Map<String, dynamic>;
  }
}
