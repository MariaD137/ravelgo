import 'api_client.dart';

/// GET /api/subscription-plans on the backend — the plans drivers can
/// subscribe to. Plan creation is available to Admin (POST) but not yet
/// exposed here; this app's Driver Subscriptions screen is read-only.
class SubscriptionApi {
  SubscriptionApi(this._client);

  final ApiClient _client;

  Future<List<Map<String, dynamic>>> listPlans() async {
    final res = await _client.get('/api/subscription-plans');
    return (res as List).cast<Map<String, dynamic>>();
  }
}
