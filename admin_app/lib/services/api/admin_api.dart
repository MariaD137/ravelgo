import 'api_client.dart';

/// The calling admin's own profile (GET/POST /api/admin/me) and the
/// weekly-reports aggregate (GET /api/admin/reports/weekly) on the
/// backend — see admin.routes.ts.
class AdminApi {
  AdminApi(this._client);

  final ApiClient _client;

  Future<Map<String, dynamic>> getMe() async {
    return await _client.get('/api/admin/me') as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> createMe({required String firstName, required String lastName, required String email}) async {
    return await _client.post('/api/admin/me', body: {'firstName': firstName, 'lastName': lastName, 'email': email})
        as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getWeeklyReport() async {
    return await _client.get('/api/admin/reports/weekly') as Map<String, dynamic>;
  }
}
