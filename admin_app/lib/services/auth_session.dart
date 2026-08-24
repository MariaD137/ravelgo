/// Seam for the admin app's not-yet-built Cognito sign-in flow.
///
/// The backend authenticates every request with a Cognito access token
/// (see backend/src/middleware/auth.ts, requireRole("Admin")) but this app
/// has no login/session code yet — connecting it to real Cognito is
/// tracked as a launch-blocking gap in docs/PRD.md, and is out of scope
/// here. [AdminApi] only needs *something* that can hand it a bearer
/// token, so it depends on this interface rather than on Cognito directly.
abstract class AuthTokenProvider {
  Future<String?> getAccessToken();
}

/// Placeholder implementation: no session exists, so every call reports
/// "not signed in" rather than fabricating a token.
class NoAuthTokenProvider implements AuthTokenProvider {
  const NoAuthTokenProvider();

  @override
  Future<String?> getAccessToken() async => null;
}
