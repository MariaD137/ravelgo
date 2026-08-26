import 'package:ravelgo_driver_app/services/auth_service.dart';

/// Seam between [DriverApi]'s REST calls and however the app currently
/// authenticates. [DriverApi] depends on this interface rather than on
/// Cognito directly, so a test can substitute a fake token source without
/// touching services/ or views/.
abstract class AuthTokenProvider {
  Future<String?> getAccessToken();

  /// Attempts to refresh the session and returns whether it succeeded.
  /// [DriverApi] calls this exactly once after a 401, then retries the
  /// original request exactly once with the (possibly new) token from
  /// [getAccessToken] — never more than that, so a still-invalid token
  /// after a successful refresh surfaces as a real error instead of
  /// looping.
  Future<bool> refreshAccessToken();

  /// Clears the session — called when a refresh attempt fails, so the app
  /// never keeps presenting itself as signed in with a token the backend
  /// will only ever reject.
  Future<void> clearSession();
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

  @override
  Future<bool> refreshAccessToken() => AuthService().refreshSession();

  @override
  Future<void> clearSession() => AuthService().signOut();
}

/// Test/placeholder implementation: no session exists, so every call
/// reports "not signed in". This intentionally does NOT fabricate a token
/// — a screen using this provider should surface the resulting 401 as a
/// real "please sign in" error, not silently succeed against a fake
/// identity. Refresh always reports failure, same reasoning: there is no
/// session to refresh.
class NoAuthTokenProvider implements AuthTokenProvider {
  const NoAuthTokenProvider();

  @override
  Future<String?> getAccessToken() async => null;

  @override
  Future<bool> refreshAccessToken() async => false;

  @override
  Future<void> clearSession() async {}
}
