import 'api_client.dart';

/// Admin's Car Paddy (vehicle license renewal) review API surface —
/// GET /api/car-paddy (Admin, paginated) and PATCH /api/car-paddy/:id
/// (approve/reject) on the backend.
class CarPaddyApi {
  CarPaddyApi(this._client);

  final ApiClient _client;

  Future<List<Map<String, dynamic>>> listAll({int page = 1, int pageSize = 20}) async {
    final res = await _client.get('/api/car-paddy', query: {'page': page, 'pageSize': pageSize})
        as Map<String, dynamic>;
    return (res['data'] as List).cast<Map<String, dynamic>>();
  }

  /// [status] must be APPROVED or REJECTED.
  Future<Map<String, dynamic>> decide(String id, String status) async {
    return await _client.patch('/api/car-paddy/$id', body: {'status': status}) as Map<String, dynamic>;
  }
}
