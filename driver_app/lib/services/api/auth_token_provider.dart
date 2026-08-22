/// Supplies the bearer token used to authenticate calls to the RavelGo
/// backend. This app has no real Cognito sign-in flow yet — login_screen.dart
/// only navigates on tap, it never calls Cognito — so there is no real
/// access token to fetch today. Wiring up real sign-in (amplify_auth_cognito
/// or an equivalent native SDK, against a real User Pool app client ID) is
/// NOT IMPLEMENTED by this change and is called out as such in the
/// remediation report; it needs a real Cognito app client to configure
/// against, which this change must not invent or hardcode.
///
/// This interface is what a real login flow will populate once that work
/// happens. Everything downstream of "having a token" — ApiClient, the
/// domain API classes, the courier UI — is real and already built against
/// it, so wiring in real Cognito later only means implementing this one
/// interface, not touching the rest of the API layer.
abstract class AuthTokenProvider {
  Future<String?> getAccessToken();
}

/// In-memory holder for the current access token. No secret is hardcoded
/// here — it only stores whatever token a real sign-in flow later obtains
/// and calls [setToken] with.
class InMemoryAuthTokenProvider implements AuthTokenProvider {
  InMemoryAuthTokenProvider._();

  static final InMemoryAuthTokenProvider instance = InMemoryAuthTokenProvider._();

  String? _token;

  void setToken(String? token) {
    _token = token;
  }

  @override
  Future<String?> getAccessToken() async => _token;
}
