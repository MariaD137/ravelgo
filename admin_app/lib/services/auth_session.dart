import 'package:ravelgo_admin/services/auth_service.dart';

/// Seam between [AdminApi]'s REST calls and however the app currently
/// authenticates (see backend/src/middleware/auth.ts, requireRole("Admin")).
/// [AdminApi] depends on this interface rather than on Cognito directly, so
/// a test can substitute a fake token source without touching services/ or
/// views/.
abstract class AuthTokenProvider {
  Future<String?> getAccessToken();
}

/// Real implementation, backed by the signed-in Cognito session in
/// [AuthService] (secure-storage-persisted access token from sign-in — see
/// auth_service.dart).
class CognitoAuthTokenProvider implements AuthTokenProvider {
  const CognitoAuthTokenProvider();

  @override
  Future<String?> getAccessToken() => AuthService().getAccessToken();
}

/// Test/placeholder implementation: no session exists, so every call
/// reports "not signed in" rather than fabricating a token.
class NoAuthTokenProvider implements AuthTokenProvider {
  const NoAuthTokenProvider();

  @override
  Future<String?> getAccessToken() async => null;
}
