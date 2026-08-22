import 'api_client.dart';

/// Admin's driver-management API surface — never imports rider_api.dart or
/// any other domain API class.
class DriverApi {
  DriverApi(this._client);

  final ApiClient _client;

  Future<List<Map<String, dynamic>>> listDrivers({int page = 1, int pageSize = 20}) async {
    final res = await _client.get('/api/drivers', query: {'page': page, 'pageSize': pageSize})
        as Map<String, dynamic>;
    return (res['data'] as List).cast<Map<String, dynamic>>();
  }

  /// Includes the driver's vehicles and documents (see drivers.routes.ts).
  Future<Map<String, dynamic>> getById(String id) async {
    return await _client.get('/api/drivers/$id') as Map<String, dynamic>;
  }

  /// [status] must be one of ACTIVE, PENDING_REVIEW, SUSPENDED.
  Future<Map<String, dynamic>> setStatus(String id, String status) async {
    return await _client.patch('/api/drivers/$id/status', body: {'status': status}) as Map<String, dynamic>;
  }
}
