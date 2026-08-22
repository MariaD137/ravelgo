import 'api_client.dart';

/// Admin's driver-document review API surface — PATCH
/// /api/documents/:id/review on the backend.
class DocumentApi {
  DocumentApi(this._client);

  final ApiClient _client;

  /// [status] must be APPROVED or REJECTED.
  Future<Map<String, dynamic>> review(String documentId, String status) async {
    return await _client.patch('/api/documents/$documentId/review', body: {'status': status})
        as Map<String, dynamic>;
  }
}
