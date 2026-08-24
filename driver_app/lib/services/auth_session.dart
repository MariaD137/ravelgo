/// Seam for the driver app's not-yet-built Cognito sign-in flow.
///
/// The backend authenticates every request with a Cognito access token
/// (see backend/src/middleware/auth.ts) but this app has no login/session
/// code yet — connecting it to real Cognito is tracked as a launch-blocking
/// gap in docs/PRD.md, and is out of scope here. [DriverApi] only needs
/// *something* that can hand it a bearer token, so it depends on this
/// interface rather than on Cognito directly — once sign-in exists, drop
/// in a real implementation and nothing in services/ or views/ has to
/// change.
abstract class AuthTokenProvider {
  Future<String?> getAccessToken();
}

/// Placeholder implementation: no session exists, so every call reports
/// "not signed in". This intentionally does NOT fabricate a token — a
/// screen using this provider should surface the resulting 401 as a real
/// "please sign in" error, not silently succeed against a fake identity.
class NoAuthTokenProvider implements AuthTokenProvider {
  const NoAuthTokenProvider();

  @override
  Future<String?> getAccessToken() async => null;
}
