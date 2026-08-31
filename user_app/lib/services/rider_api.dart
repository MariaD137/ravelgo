import 'package:ravelgo_user_app/services/api_client.dart';
import 'package:ravelgo_user_app/services/auth_service.dart';

/// Rider-facing backend calls, built on [ApiClient].
class RiderApi {
  /// Ensure a rider profile row exists (the backend upserts by Cognito sub).
  /// Best-effort — safe to call on every sign-in. Requires the user to be in
  /// the Cognito "Rider" group, or the backend returns 403.
  static Future<void> provisionMe() async {
    final email = AuthService.email;
    if (email == null || email.isEmpty) return;
    await ApiClient.post('/api/riders/me', {
      'firstName': (AuthService.givenName?.isNotEmpty ?? false) ? AuthService.givenName : 'Rider',
      'lastName': (AuthService.familyName?.isNotEmpty ?? false) ? AuthService.familyName : 'User',
      'email': email,
    });
  }

  /// The signed-in rider's profile from the backend.
  static Future<Map<String, dynamic>?> getMe() async {
    final data = await ApiClient.get('/api/riders/me');
    return data is Map<String, dynamic> ? data : null;
  }
}
