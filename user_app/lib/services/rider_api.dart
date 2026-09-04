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

  /// Update the signed-in rider's own name/phone. Email isn't editable here —
  /// it's tied to the Cognito identity used to sign in.
  static Future<Map<String, dynamic>?> updateMe({
    String? firstName,
    String? lastName,
    String? phoneNumber,
  }) async {
    final body = <String, dynamic>{
      if (firstName != null) 'firstName': firstName,
      if (lastName != null) 'lastName': lastName,
      if (phoneNumber != null) 'phoneNumber': phoneNumber,
    };
    final data = await ApiClient.patch('/api/riders/me', body);
    return data is Map<String, dynamic> ? data : null;
  }
}
