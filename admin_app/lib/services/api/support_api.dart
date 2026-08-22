import 'api_client.dart';

/// Admin's support-ticket API surface — GET/PATCH /api/support-tickets on
/// the backend. Ticket creation is a rider/driver action, not an admin one,
/// so this class is read/triage-only by design.
class SupportApi {
  SupportApi(this._client);

  final ApiClient _client;

  Future<List<Map<String, dynamic>>> listAll({int page = 1, int pageSize = 20}) async {
    final res = await _client.get('/api/support-tickets', query: {'page': page, 'pageSize': pageSize})
        as Map<String, dynamic>;
    return (res['data'] as List).cast<Map<String, dynamic>>();
  }

  /// [status] must be one of OPEN, IN_PROGRESS, RESOLVED.
  Future<Map<String, dynamic>> setStatus(String ticketId, String status) async {
    return await _client.patch('/api/support-tickets/$ticketId/status', body: {'status': status})
        as Map<String, dynamic>;
  }
}
