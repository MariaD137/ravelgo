import 'api_client.dart';

/// The calling rider's own profile — GET/POST /api/riders/me on the
/// backend. Cognito sign-up creates no Postgres row by itself, so the app
/// calls createMe() once right after first authentication (same bootstrap
/// pattern as driver_app's POST /drivers/me and admin_app's POST /admin/me).
class RiderApi {
  RiderApi(this._client);

  final ApiClient _client;

  Future<Map<String, dynamic>> getMe() async {
    return await _client.get('/api/riders/me') as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> createMe({
    required String firstName,
    required String lastName,
    required String email,
    String? phoneNumber,
  }) async {
    return await _client.post(
          '/api/riders/me',
          body: {
            'firstName': firstName,
            'lastName': lastName,
            'email': email,
            if (phoneNumber != null) 'phoneNumber': phoneNumber,
          },
        )
        as Map<String, dynamic>;
  }

  /// Updates name/phone only — not email, which stays tied to the Cognito
  /// identity the profile was bootstrapped from (see riders.routes.ts).
  Future<Map<String, dynamic>> updateMe({String? firstName, String? lastName, String? phoneNumber}) async {
    return await _client.patch(
          '/api/riders/me',
          body: {
            if (firstName != null) 'firstName': firstName,
            if (lastName != null) 'lastName': lastName,
            if (phoneNumber != null) 'phoneNumber': phoneNumber,
          },
        )
        as Map<String, dynamic>;
  }
}
