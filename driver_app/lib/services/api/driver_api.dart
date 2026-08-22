import 'api_client.dart';

/// The driver's own profile — GET/POST /api/drivers/me on the backend.
class DriverApi {
  DriverApi(this._client);

  final ApiClient _client;

  Future<Map<String, dynamic>> getMyProfile() async {
    return await _client.get('/api/drivers/me') as Map<String, dynamic>;
  }
}
