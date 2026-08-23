import 'api_client.dart';

/// The driver's own profile and real-time presence — GET/POST
/// /api/drivers/me and PATCH /api/drivers/me/online on the backend.
class DriverApi {
  DriverApi(this._client);

  final ApiClient _client;

  Future<Map<String, dynamic>> getMyProfile() async {
    return await _client.get('/api/drivers/me') as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> createMyProfile({
    required String firstName,
    required String lastName,
    required String email,
    String? phoneNumber,
    String preferredLanguage = 'English',
  }) async {
    return await _client.post(
          '/api/drivers/me',
          body: {
            'firstName': firstName,
            'lastName': lastName,
            'email': email,
            if (phoneNumber != null) 'phoneNumber': phoneNumber,
            'preferredLanguage': preferredLanguage,
          },
        )
        as Map<String, dynamic>;
  }

  /// Sets real-time presence. matching.ts only considers `online: true`
  /// drivers eligible for a new ride — this is the real backend effect
  /// behind the driver_home_screen "online/offline" switch, not just a
  /// local toggle.
  Future<Map<String, dynamic>> setOnline(bool online) async {
    return await _client.patch('/api/drivers/me/online', body: {'online': online}) as Map<String, dynamic>;
  }
}
