import 'package:flutter/foundation.dart' show kReleaseMode;

/// Where an [AuthProvider]-backed session currently stands. Kept explicit
/// rather than inferred from navigation — a screen should never treat "the
/// user tapped a button and got routed somewhere" as proof of
/// authentication; it should read this instead.
enum AuthStatus {
  /// No signed-in session. The starting state, and where [DevOnlyAuthProvider]
  /// and [UnauthenticatedAuthProvider] both begin.
  unauthenticated,

  /// A login attempt is in flight.
  authenticating,

  /// [AuthProvider.login] succeeded; [AuthProvider.getAccessToken] returns
  /// a token.
  authenticated,

  /// The most recent login attempt failed. Distinct from [unauthenticated]
  /// so the UI can show why, instead of silently resetting to a blank form.
  authenticationFailed,
}

/// The authentication boundary every API client and screen depends on,
/// never on a specific identity provider directly. This app has no real
/// Cognito sign-in flow yet — but once one is wired up (via
/// amplify_auth_cognito or an equivalent native SDK, against a real Admin
/// User Pool app client this change must not invent or hardcode), a real
/// implementation of this same interface drops in without touching
/// ApiClient, the domain API classes, or any screen — they all already
/// depend on this abstraction, not on Cognito.
abstract class AuthProvider {
  /// Authenticates with the identity provider and stores the resulting
  /// session so [getAccessToken] and [isAuthenticated] reflect it.
  Future<void> login({required String username, required String password});

  /// Clears the current session. [isAuthenticated] returns false and
  /// [getAccessToken] returns null afterward.
  Future<void> logout();

  /// The current bearer token to send as `Authorization: Bearer <token>`,
  /// or null if there is no signed-in session.
  Future<String?> getAccessToken();

  /// Whether a session is currently active.
  Future<bool> isAuthenticated();
}

/// DEVELOPMENT ONLY. There is no real Cognito sign-in wired into this app
/// yet — this class exists only so the API layer and screens have
/// something to run against locally before that work happens. It is not a
/// security control: it stores nothing durably or securely, and [login]
/// deliberately fails loudly rather than fabricating a token that looks
/// real but isn't. An admin session compromised through a stubbed auth
/// provider is a materially worse outcome than a rider or driver one, so
/// this is guarded the same way as the other apps' dev providers, not
/// loosened for convenience.
///
/// Guarded, not just labeled: the constructor throws in a release build
/// rather than relying on nobody accidentally wiring this into production.
/// The check is a plain `if`, not an `assert()` — `assert()` bodies are
/// stripped from release builds entirely, so an assert-only guard would be
/// silently removed in exactly the build where it matters most.
class DevOnlyAuthProvider implements AuthProvider {
  DevOnlyAuthProvider() {
    if (kReleaseMode) {
      throw StateError(
        'DevOnlyAuthProvider must never be constructed in a release build. '
        'Wire in a real AuthProvider (Cognito) before shipping.',
      );
    }
  }

  static final DevOnlyAuthProvider instance = DevOnlyAuthProvider();

  String? _token;

  /// Dev-only hook to simulate having a session without a real sign-in
  /// flow, e.g. from a debug menu. Not part of [AuthProvider] — callers
  /// that only depend on the interface can never reach this.
  void setToken(String? token) {
    _token = token;
  }

  @override
  Future<void> login({required String username, required String password}) async {
    throw UnimplementedError(
      'DevOnlyAuthProvider.login is not implemented — there is no real '
      'Cognito integration yet. Use setToken() for local development, or '
      'construct ApiClient with a real AuthProvider once Cognito is deployed.',
    );
  }

  @override
  Future<void> logout() async {
    _token = null;
  }

  @override
  Future<String?> getAccessToken() async => _token;

  @override
  Future<bool> isAuthenticated() async => _token != null;
}

/// The production-safe fallback everywhere a real, Cognito-backed
/// [AuthProvider] doesn't exist yet. Unlike [DevOnlyAuthProvider], this one
/// carries no release-mode guard because it needs none: it never holds a
/// token, never claims a session, and [login] fails by explaining why
/// rather than by throwing an implementation-detail error. Safe to
/// construct anywhere, in any build mode — that safety is exactly why
/// [createDefaultAuthProvider] returns this in release builds instead of
/// [DevOnlyAuthProvider]. An admin session is a materially worse thing to
/// get wrong than a rider or driver one, so this fallback is just as strict
/// as those apps' — it never authenticates, ever, without a real provider.
class UnauthenticatedAuthProvider implements AuthProvider {
  @override
  Future<void> login({required String username, required String password}) async {
    throw StateError(
      'Sign-in is not available yet — this build has no authentication '
      'provider configured (Cognito is not deployed). This is expected '
      'pre-launch behavior, not a bug: the app must never fabricate a '
      'session to work around it.',
    );
  }

  @override
  Future<void> logout() async {}

  @override
  Future<String?> getAccessToken() async => null;

  @override
  Future<bool> isAuthenticated() async => false;
}

/// The one place this app decides which [AuthProvider] implementation is
/// in effect — every other constructor (ApiClient's default, the Login
/// screen's default parameter) calls this instead of choosing for itself,
/// so there is exactly one `kReleaseMode` branch to audit. Swap the
/// non-release branch for a real `CognitoAuthProvider` once a User Pool
/// exists; the release branch must stay [UnauthenticatedAuthProvider] until
/// a real one is ready to replace it — never [DevOnlyAuthProvider], which
/// would throw, and never anything that fabricates a session.
AuthProvider createDefaultAuthProvider() {
  if (kReleaseMode) return UnauthenticatedAuthProvider();
  return DevOnlyAuthProvider.instance;
}
