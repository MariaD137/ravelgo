import 'api_client.dart';

/// Admin's courier-monitoring API surface — never imports rider_api.dart,
/// driver_api.dart, or rental_api.dart. Admins only monitor courier
/// requests here (GET /api/courier-requests); accept/status-update actions
/// belong to the driver, not the admin console.
class CourierApi {
  CourierApi(this._client);

  final ApiClient _client;

  Future<List<Map<String, dynamic>>> listAll({int page = 1, int pageSize = 20}) async {
    final res = await _client.get('/api/courier-requests', query: {'page': page, 'pageSize': pageSize})
        as Map<String, dynamic>;
    return (res['data'] as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> getById(String id) async {
    return await _client.get('/api/courier-requests/$id') as Map<String, dynamic>;
  }
}
