import 'api_client.dart';

/// Admin's trip-monitoring API surface — GET /api/trips (paginated, all
/// trips) and GET /api/trips/:id (single trip with rider/driver detail) on
/// the backend. Status transitions themselves stay driver/Admin-owned via
/// PATCH /api/trips/:id/status, exposed here only for the Admin dispute/
/// cancellation actions this app's trip-monitoring screens need.
class TripApi {
  TripApi(this._client);

  final ApiClient _client;

  Future<List<Map<String, dynamic>>> listAll({int page = 1, int pageSize = 20}) async {
    final res = await _client.get('/api/trips', query: {'page': page, 'pageSize': pageSize})
        as Map<String, dynamic>;
    return (res['data'] as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> getById(String id) async {
    return await _client.get('/api/trips/$id') as Map<String, dynamic>;
  }

  /// [status] must be one of MATCHED, IN_PROGRESS, COMPLETED, CANCELLED, DISPUTED.
  Future<Map<String, dynamic>> setStatus(String id, String status) async {
    return await _client.patch('/api/trips/$id/status', body: {'status': status}) as Map<String, dynamic>;
  }
}
