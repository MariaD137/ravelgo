import 'api_client.dart';

/// Loyalty tiers and redeemable promotions — GET /api/loyalty-tiers,
/// GET /api/promotions, POST /api/promotions on the backend.
class LoyaltyApi {
  LoyaltyApi(this._client);

  final ApiClient _client;

  Future<List<Map<String, dynamic>>> listTiers() async {
    final res = await _client.get('/api/loyalty-tiers');
    return (res as List).cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> listPromotions() async {
    final res = await _client.get('/api/promotions');
    return (res as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> createPromotion({
    required String code,
    required String description,
    required double discountPercent,
  }) async {
    return await _client.post(
          '/api/promotions',
          body: {'code': code, 'description': description, 'discountPercent': discountPercent},
        )
        as Map<String, dynamic>;
  }
}
