import 'package:ravelgo_driver_app/services/auth_service.dart';

/// Seam between [DriverApi]'s REST calls and however the app currently
/// authenticates. [DriverApi] depends on this interface rather than on
/// Cognito directly, so a test can substitute a fake token source without
/// touching services/ or views/.
abstract class AuthTokenProvider {
  Future<String?> getAccessToken();
}

/// Real implementation, backed by the signed-in Cognito session in
/// [AuthService] (secure-storage-persisted access token from sign-in/
/// sign-up — see auth_service.dart). Returns null when there's no session,
/// same as [NoAuthTokenProvider], so an unauthenticated call still
/// surfaces the backend's real 401 instead of silently succeeding.
class CognitoAuthTokenProvider implements AuthTokenProvider {
  const CognitoAuthTokenProvider();

  @override
  Future<String?> getAccessToken() => AuthService().getAccessToken();
}

/// Test/placeholder implementation: no session exists, so every call
/// reports "not signed in". This intentionally does NOT fabricate a token
/// — a screen using this provider should surface the resulting 401 as a
/// real "please sign in" error, not silently succeed against a fake
/// identity.
class NoAuthTokenProvider implements AuthTokenProvider {
  const NoAuthTokenProvider();

  @override
  Future<String?> getAccessToken() async => null;
}
