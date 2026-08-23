import 'api_client.dart';

/// Admin's emergency/fraud alert API surface — GET /api/emergency-alerts
/// (Admin, paginated, all alert types) and PATCH
/// /api/emergency-alerts/:id/status on the backend. Both the "SOS" and
/// "Fraud" admin screens read from this same endpoint, filtered by
/// EmergencyAlert.type — there is no separate fraud-detection system.
class AlertsApi {
  AlertsApi(this._client);

  final ApiClient _client;

  Future<List<Map<String, dynamic>>> listAll({int page = 1, int pageSize = 20}) async {
    final res = await _client.get('/api/emergency-alerts', query: {'page': page, 'pageSize': pageSize})
        as Map<String, dynamic>;
    return (res['data'] as List).cast<Map<String, dynamic>>();
  }

  /// [status] must be ACKNOWLEDGED or RESOLVED.
  Future<Map<String, dynamic>> setStatus(String id, String status) async {
    return await _client.patch('/api/emergency-alerts/$id/status', body: {'status': status})
        as Map<String, dynamic>;
  }
}
