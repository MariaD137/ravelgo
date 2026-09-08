import 'dart:convert';
import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:amplify_push_notifications_pinpoint/amplify_push_notifications_pinpoint.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ravelgo_driver_app/services/push_token_api.dart';

/// Wires the app up to real device push notifications, end to end:
///
///   FCM/APNs device token (AWS Amplify's Push Notifications category, used
///   ONLY for token acquisition and tap events — no Firebase SDK anywhere)
///   -> POST /api/notifications/device-tokens (push_token_api.dart)
///   -> backend stores it (PushToken) and later sends through AWS Pinpoint
///      (backend/src/services/push.ts) when a real event happens
///      (backend/src/lib/notifications.ts) — e.g. a trip this driver
///      completed
///   -> this device receives it; tapping it navigates to the referenced
///      trip/delivery, same as an in-app notification tap
///
/// Amplify here is configured against an unauthenticated-only Cognito
/// Identity Pool created solely to vend anonymous AWS credentials for the
/// push plugin's own on-device housekeeping calls
/// (infra/lib/auth-stack.ts's PushIdentityPool) — it is never linked to, and
/// never touches, the real RavelGo sign-in. AuthService
/// (amazon_cognito_identity_dart_2) remains the only thing that actually
/// authenticates a driver; nothing here calls Amplify.Auth.signIn or reads
/// its session. Ported from the identical mechanism in user_app.
///
/// Every public method is a safe no-op until real AWS_REGION,
/// PINPOINT_APPLICATION_ID and PUSH_IDENTITY_POOL_ID values are supplied via
/// .env — exactly like ApiClient.isConfigured elsewhere in this app degrades
/// when its own .env values are absent.
class PushNotificationService {
  static const _tokenPrefsKey = 'push_device_token';

  static bool _configuring = false;
  static bool _configured = false;

  // try/catch matches ApiClient.isConfigured's own pattern: dotenv.env throws
  // NotInitializedError if dotenv.load() hasn't run yet (e.g. a widget test
  // that never calls it) — reading these must never crash the app, it should
  // just mean "not configured".
  static String _readEnv(String key) {
    try {
      return (dotenv.env[key] ?? '').trim();
    } catch (_) {
      return '';
    }
  }

  static String get _region => _readEnv('AWS_REGION');
  static String get _pinpointApplicationId => _readEnv('PINPOINT_APPLICATION_ID');
  static String get _identityPoolId => _readEnv('PUSH_IDENTITY_POOL_ID');

  /// True only once a real Pinpoint application + identity pool have
  /// actually been supplied — the feature stays entirely inert otherwise.
  static bool get isConfigured =>
      _region.isNotEmpty && _pinpointApplicationId.isNotEmpty && _identityPoolId.isNotEmpty;

  static String get _platform => defaultTargetPlatform == TargetPlatform.iOS ? 'IOS' : 'ANDROID';

  static String _amplifyConfig() => jsonEncode({
        'UserAgent': 'aws-amplify-cli/2.0',
        'Version': '1.0',
        'auth': {
          'plugins': {
            'awsCognitoAuthPlugin': {
              // Identity-pool-only: no CognitoUserPool section, so this
              // Amplify Auth plugin instance has no notion of a RavelGo user
              // or session — it can only ever vend anonymous credentials.
              'CredentialsProvider': {
                'CognitoIdentity': {
                  'Default': {'PoolId': _identityPoolId, 'Region': _region},
                },
              },
            },
          },
        },
        'notifications': {
          'plugins': {
            'awsPinpointPushNotificationsPlugin': {
              'pinpointAnalytics': {'appId': _pinpointApplicationId, 'region': _region},
              'pinpointTargeting': {'region': _region},
            },
          },
        },
      });

  /// Call once (e.g. app start, or right after sign-in). Idempotent — safe
  /// to call from multiple places. Never throws: any failure here is a
  /// missing enhancement, not a reason to block using the app.
  static Future<void> configureAndRegister() async {
    if (!isConfigured) return;
    if (kIsWeb) return; // web push is a distinct integration; out of scope here
    if (defaultTargetPlatform != TargetPlatform.android && defaultTargetPlatform != TargetPlatform.iOS) return;
    if (_configured || _configuring) return;
    _configuring = true;

    try {
      await Amplify.addPlugins([
        AmplifyAuthCognito(),
        AmplifyPushNotificationsPinpoint(),
      ]);
      await Amplify.configure(_amplifyConfig());
      _configured = true;

      await Amplify.Notifications.Push.requestPermissions();

      Amplify.Notifications.Push.onTokenReceived.listen(
        _registerToken,
        onError: (Object _) {},
      );

      Amplify.Notifications.Push.onNotificationOpened.listen(
        _handleNotificationOpened,
        onError: (Object _) {},
      );
    } on AmplifyAlreadyConfiguredException {
      _configured = true;
    } catch (_) {
      // Best-effort — push is an enhancement, never a requirement to use the app.
    } finally {
      _configuring = false;
    }
  }

  static Future<void> _registerToken(String token) async {
    if (token.isEmpty) return;
    try {
      await PushTokenApi.register(token: token, platform: _platform);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_tokenPrefsKey, token);
    } catch (_) {
      // Best-effort; a future token refresh or app open will retry.
    }
  }

  /// Called when the driver taps a delivered push notification. Reads the
  /// same referenceType/referenceId data payload the backend attaches to
  /// every push (see backend/src/lib/notifications.ts) — actual navigation
  /// is wired by whichever screen is listening via [onNotificationTapped].
  static void Function(String? referenceType, String? referenceId)? onNotificationTapped;

  static void _handleNotificationOpened(PushNotificationMessage message) {
    final data = message.data;
    onNotificationTapped?.call(
      data['referenceType']?.toString(),
      data['referenceId']?.toString(),
    );
  }

  /// Call on logout so a future push never reaches a signed-out session.
  static Future<void> unregister() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(_tokenPrefsKey);
      if (token != null && token.isNotEmpty) {
        await PushTokenApi.unregister(token);
        await prefs.remove(_tokenPrefsKey);
      }
    } catch (_) {
      // Best-effort — logout must still succeed even if this fails.
    }
  }
}
