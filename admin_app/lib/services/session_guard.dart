import 'package:ravelgo_admin/services/auth_service.dart';

/// Centralised reaction to "the backend rejected this session" (HTTP 401).
///
/// Every screen used to deal with a 401 on its own, which in practice meant
/// not dealing with it at all: an expired or revoked session surfaced as
/// whatever generic error the screen showed for any failure, and the app
/// stayed sitting on a signed-in UI it could no longer load anything into.
///
/// The rule is now one rule, applied inside [ApiClient] for every request:
///
///   1. A 401 gets ONE forced token refresh. `validAccessToken()` only
///      refreshes a token it can see has expired, so it never notices one
///      the backend has revoked — the refresh token may well still be good.
///   2. If that refresh works, the original request is retried exactly once.
///   3. If it doesn't work, or the retry is refused too, the local session is
///      cleared and the app goes back to the sign-in screen with a single
///      explanation instead of an error on a dead screen.
///
/// Nothing here decides who the user is or what they may do — the backend
/// still makes every authentication and authorization decision. This only
/// stops the app clinging to a session the backend has already rejected.
class SessionGuard {
  SessionGuard._();

  static const expiredMessage =
      'Your session has expired. Please sign in again.';

  /// Forces a token refresh. Swappable for tests.
  static Future<bool> Function() refreshSession = AuthService.refreshTokens;

  /// Clears the local session. Swappable for tests.
  static Future<void> Function() clearSession = AuthService.signOut;

  /// Whether a session is still held locally. Swappable for tests.
  static bool Function() hasSession = () => AuthService.isSignedIn;

  /// Set once by main.dart: returns the app to the sign-in screen and shows
  /// [expiredMessage]. Left null in tests and before the first frame, where
  /// clearing the session above is the whole of the job.
  static void Function()? onSessionExpired;

  // Screens fire requests in parallel, so one dead session must not turn
  // into N refreshes and N trips back to the sign-in screen.
  static Future<bool>? _inFlightRefresh;
  static Future<void>? _inFlightExpiry;

  /// One forced refresh, shared by every caller that races into it.
  static Future<bool> tryRefresh() {
    return _inFlightRefresh ??= _refresh().whenComplete(() {
      _inFlightRefresh = null;
    });
  }

  static Future<bool> _refresh() async {
    try {
      return await refreshSession();
    } catch (_) {
      return false;
    }
  }

  /// Give up on the session: sign out locally and return to sign-in. A no-op
  /// once the session is already gone, so the second and later 401s of a
  /// burst cost nothing.
  static Future<void> expire() {
    if (!hasSession()) return Future.value();
    return _inFlightExpiry ??= _expire().whenComplete(() {
      _inFlightExpiry = null;
    });
  }

  static Future<void> _expire() async {
    try {
      await clearSession();
    } catch (_) {
      // Best effort — the session is being abandoned either way.
    }
    onSessionExpired?.call();
  }

  /// Test hook: forget any in-flight refresh/expiry.
  static void reset() {
    _inFlightRefresh = null;
    _inFlightExpiry = null;
  }
}
