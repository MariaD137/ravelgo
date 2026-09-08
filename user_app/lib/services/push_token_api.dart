import 'package:ravelgo_user_app/services/api_client.dart';

/// Device-token registration, proxied through the RavelGo backend
/// (POST/DELETE /api/notifications/device-tokens). Ownership always comes
/// from the caller's authenticated Cognito identity — there is no user id in
/// either request. Pure HTTP; carries no Firebase/SNS dependency itself, so
/// it works regardless of whether push is actually configured for this build.
class PushTokenApi {
  /// Register (or re-register) this device's token. Returns whether the
  /// backend actually has an SNS platform application configured for
  /// [platform] — false just means the token was recorded but no push will
  /// be sent yet (e.g. staging with no SNS credentials set up).
  static Future<bool> register({required String token, required String platform}) async {
    final data = await ApiClient.post('/api/notifications/device-tokens', {
      'token': token,
      'platform': platform,
    });
    return data is Map && data['registered'] == true;
  }

  /// Unregister this device's token (e.g. on logout), so a future push never
  /// reaches a signed-out session's device.
  static Future<void> unregister(String token) async {
    await ApiClient.delete('/api/notifications/device-tokens', {'token': token});
  }
}
