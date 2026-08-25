import 'package:ravelgo_admin/services/auth_service.dart';

/// Seam between [AdminApi]'s REST calls and however the app currently
/// authenticates (see backend/src/middleware/auth.ts, requireRole("Admin")).
/// [AdminApi] depends on this interface rather than on Cognito directly, so
/// a test can substitute a fake token source without touching services/ or
/// views/.
abstract class AuthTokenProvider {
  Future<String?> getAccessToken();

  /// Attempts to refresh the session and returns whether it succeeded.
  /// [AdminApi] calls this exactly once after a 401, then retries the
  /// original request exactly once with the (possibly new) token from
  /// [getAccessToken] — never more than that.
  Future<bool> refreshAccessToken();

  /// Clears the session — called when a refresh attempt fails, so the app
  /// never keeps presenting itself as signed in with a token the backend
  /// will only ever reject.
  Future<void> clearSession();
}

/// Real implementation, backed by the signed-in Cognito session in
/// [AuthService] (secure-storage-persisted access token from sign-in — see
/// auth_service.dart).
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
/// reports "not signed in" rather than fabricating a token. Refresh
/// always reports failure — there is no session to refresh.
class NoAuthTokenProvider implements AuthTokenProvider {
  const NoAuthTokenProvider();

  @override
  Future<String?> getAccessToken() async => null;

  @override
  Future<bool> refreshAccessToken() async => false;

  @override
  Future<void> clearSession() async {}
}
