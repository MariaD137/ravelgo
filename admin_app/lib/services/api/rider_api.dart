import 'api_client.dart';

/// Admin's rider-management API surface — never imports driver_api.dart or
/// any other domain API class.
class RiderApi {
  RiderApi(this._client);

  final ApiClient _client;

  Future<List<Map<String, dynamic>>> listRiders({int page = 1, int pageSize = 20}) async {
    final res = await _client.get('/api/riders', query: {'page': page, 'pageSize': pageSize})
        as Map<String, dynamic>;
    return (res['data'] as List).cast<Map<String, dynamic>>();
  }

  /// Includes the rider's recent trip history (see riders.routes.ts).
  Future<Map<String, dynamic>> getById(String id) async {
    return await _client.get('/api/riders/$id') as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> setSuspended(String id, bool suspended) async {
    return await _client.patch('/api/riders/$id/status', body: {'suspended': suspended})
        as Map<String, dynamic>;
  }
}
