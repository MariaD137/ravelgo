import 'package:amazon_cognito_identity_dart_2/cognito.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists the Cognito session across app restarts / browser refreshes.
///
/// amazon_cognito_identity_dart_2 stores the access, id and (long-lived)
/// refresh tokens through whatever [CognitoStorage] the pool is given. Backing
/// it with SharedPreferences means the session survives a reload — on Flutter
/// Web that is localStorage (per-origin, cleared only on explicit logout or
/// when the refresh token itself expires); on mobile it is the platform's
/// key/value store. The access token stays short-lived (~1h) and is refreshed
/// from the stored refresh token, so persistence does not weaken security.
class _CognitoPrefsStorage extends CognitoStorage {
  _CognitoPrefsStorage(this._prefs);
  final SharedPreferences _prefs;

  @override
  Future<dynamic> getItem(String key) async => _prefs.getString(key);

  @override
  Future<dynamic> setItem(String key, dynamic value) async {
    await _prefs.setString(key, value.toString());
    return value;
  }

  @override
  Future<dynamic> removeItem(String key) async {
    final existing = _prefs.getString(key);
    await _prefs.remove(key);
    return existing;
  }

  @override
  Future<void> clear() async {
    await _prefs.clear();
  }
}

/// Real authentication against the RavelGo Cognito user pool.
///
/// Reads the pool + client IDs from the environment (.env, produced at build
/// time from the deployed Auth stack). Sign-up sends a real 6-digit code to
/// the user's email; confirmation and sign-in return Cognito tokens that the
/// app attaches to backend API calls.
class AuthService {
  static CognitoUserPool? _poolInstance;

  /// Build the persistent-storage-backed pool. Called once from main() after
  /// dotenv is loaded and before the first frame. Falls back to the default
  /// in-memory pool if storage can't be opened, so the app still runs.
  static Future<void> init() async {
    if (_poolInstance != null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _poolInstance = CognitoUserPool(
        dotenv.env['COGNITO_USER_POOL_ID'] ?? '',
        dotenv.env['COGNITO_CLIENT_ID'] ?? '',
        storage: _CognitoPrefsStorage(prefs),
      );
    } catch (_) {
      _poolInstance = CognitoUserPool(
        dotenv.env['COGNITO_USER_POOL_ID'] ?? '',
        dotenv.env['COGNITO_CLIENT_ID'] ?? '',
      );
    }
  }

  static CognitoUserPool get _pool {
    // If init() somehow hasn't run (e.g. a widget test), fall back to a plain
    // in-memory pool so calls don't NPE.
    return _poolInstance ??= CognitoUserPool(
      dotenv.env['COGNITO_USER_POOL_ID'] ?? '',
      dotenv.env['COGNITO_CLIENT_ID'] ?? '',
    );
  }

  static CognitoUserSession? session;
  static CognitoUser? currentUser;
  static String? accessToken;
  static String? idToken;
  static String? email;
  static String? givenName;
  static String? familyName;

  static bool get isSignedIn => accessToken != null;

  /// True only when the app was built with real Cognito settings. Lets the UI
  /// give a clear message instead of a cryptic error if config is missing.
  static bool get isConfigured =>
      (dotenv.env['COGNITO_USER_POOL_ID'] ?? '').isNotEmpty &&
      (dotenv.env['COGNITO_CLIENT_ID'] ?? '').isNotEmpty;

  /// Restore a persisted session on startup. Returns true only when a valid
  /// (or successfully refreshed) session exists. getSession() transparently
  /// exchanges the stored refresh token for fresh access/id tokens when the
  /// access token has expired.
  static Future<bool> restoreSession() async {
    try {
      final user = await _pool.getCurrentUser();
      if (user == null) return false;
      final s = await user.getSession();
      if (s == null || !s.isValid()) return false;
      _applySession(user, s);
      return accessToken != null;
    } catch (_) {
      return false;
    }
  }

  /// The access token the API client sends. Refreshes first if the current
  /// access token has expired, so long-lived sessions keep working.
  static Future<String?> validAccessToken() async {
    final s = session;
    if (s != null && s.isValid()) return accessToken;
    try {
      final user = currentUser ?? await _pool.getCurrentUser();
      if (user == null) return null;
      final refreshed = await user.getSession();
      if (refreshed != null && refreshed.isValid()) {
        _applySession(user, refreshed);
        return accessToken;
      }
    } catch (_) {
      // Refresh failed (refresh token expired/revoked) — treat as signed out.
    }
    return null;
  }

  /// Whether the CURRENT access token carries the given Cognito group. The
  /// backend authorizes every Driver route off the `cognito:groups` claim of
  /// the token it receives (backend/src/middleware/auth.ts requireRole), so
  /// what matters is what this token says — not what Cognito itself now
  /// believes about the user.
  static bool hasGroup(String group) {
    final s = session;
    if (s == null) return false;
    try {
      final groups = s.getAccessToken().decodePayload()['cognito:groups'];
      return groups is List && groups.contains(group);
    } catch (_) {
      return false;
    }
  }

  /// Force a token refresh via the stored refresh token, even though the
  /// current access token is still valid.
  ///
  /// Group membership is baked into a token at issue time. After
  /// POST /api/drivers/apply the SERVER adds the user to the "Driver" group,
  /// but the access token the app already holds (valid for up to an hour —
  /// see accessTokenValidity in infra/lib/auth-stack.ts) still lacks it, so
  /// every Driver-only route (GET /drivers/me, documents, vehicles) 403s
  /// until the token naturally expires. getSession() deliberately reuses a
  /// still-valid token, so this is the only way to pick the new group up
  /// immediately. Returns true if a fresh session was applied.
  static Future<bool> refreshTokens() async {
    try {
      final user = currentUser ?? await _pool.getCurrentUser();
      final refreshToken = session?.getRefreshToken() ?? (await user?.getSession())?.getRefreshToken();
      if (user == null || refreshToken == null || refreshToken.getToken() == null) return false;
      final refreshed = await user.refreshSession(refreshToken);
      if (refreshed == null || !refreshed.isValid()) return false;
      _applySession(user, refreshed);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Make sure the access token we send carries the "Driver" group. If it
  /// already does, nothing happens. Otherwise force one refresh and report
  /// whether the fresh token has it — false means Cognito still does not
  /// list this user in the group (the application hasn't been submitted, or
  /// the server-side grant failed), which only POST /drivers/apply can fix.
  static Future<bool> ensureDriverGroupOnToken() async {
    if (hasGroup('Driver')) return true;
    if (!await refreshTokens()) return false;
    return hasGroup('Driver');
  }

  static void _applySession(CognitoUser user, CognitoUserSession s) {
    currentUser = user;
    session = s;
    accessToken = s.getAccessToken().getJwtToken();
    idToken = s.getIdToken().getJwtToken();
    final claims = s.getIdToken().decodePayload();
    email = claims['email']?.toString() ?? email;
    givenName = claims['given_name']?.toString() ?? givenName;
    familyName = claims['family_name']?.toString() ?? familyName;
  }

  /// Create an account. Cognito emails a 6-digit confirmation code.
  static Future<void> signUp({
    required String email,
    required String password,
    required String givenName,
    required String familyName,
  }) async {
    await _pool.signUp(
      email,
      password,
      userAttributes: [
        AttributeArg(name: 'email', value: email),
        AttributeArg(name: 'given_name', value: givenName),
        AttributeArg(name: 'family_name', value: familyName),
      ],
    );
  }

  /// Confirm the account with the emailed code.
  static Future<void> confirm({required String email, required String code}) async {
    final user = CognitoUser(email, _pool);
    await user.confirmRegistration(code);
  }

  /// Ask Cognito to email a fresh confirmation code.
  static Future<void> resendCode({required String email}) async {
    final user = CognitoUser(email, _pool);
    await user.resendConfirmationCode();
  }

  /// Ask Cognito to email a password-reset code.
  static Future<void> forgotPassword({required String email}) async {
    final user = CognitoUser(email, _pool);
    await user.forgotPassword();
  }

  /// Complete a password reset with the emailed code and a new password.
  static Future<void> confirmForgotPassword({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    final user = CognitoUser(email, _pool);
    await user.confirmPassword(code, newPassword);
  }

  /// Change the password for the currently signed-in user.
  static Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    final user = currentUser;
    if (user == null) {
      throw CognitoClientException('Please sign in again to change your password.');
    }
    await user.changePassword(oldPassword, newPassword);
  }

  /// Set by signIn() when Cognito responds with the SOFTWARE_TOKEN_MFA
  /// challenge. Consumed by submitMfaCode().
  static CognitoUser? _pendingMfaUser;

  /// Sign in and persist the resulting tokens (via the pool's storage) for
  /// API calls and across reloads.
  ///
  /// Throws CognitoUserTotpRequiredException for an account that has TOTP
  /// MFA enrolled. The pool is shared by all three apps (infra/lib/auth-stack.ts),
  /// so an account that enrolled via the Admin App gets this challenge here
  /// too — the caller must collect the 6-digit authenticator code and call
  /// submitMfaCode() to finish signing in.
  static Future<void> signIn({required String email, required String password}) async {
    final user = CognitoUser(email, _pool);
    AuthService.email = email;
    try {
      final s = await user.authenticateUser(
        AuthenticationDetails(username: email, password: password),
      );
      if (s != null) {
        _applySession(user, s);
      }
    } on CognitoUserTotpRequiredException {
      _pendingMfaUser = user;
      rethrow;
    }
  }

  /// Completes sign-in after signIn() threw CognitoUserTotpRequiredException,
  /// by submitting the 6-digit code from the user's authenticator app.
  static Future<void> submitMfaCode({required String code}) async {
    final user = _pendingMfaUser;
    if (user == null) {
      throw CognitoClientException('Your session expired — please sign in again.');
    }
    final s = await user.sendMFACode(code, 'SOFTWARE_TOKEN_MFA');
    if (s != null) {
      _applySession(user, s);
    }
    _pendingMfaUser = null;
  }

  /// Clear the session locally and from persistent storage.
  static Future<void> signOut() async {
    try {
      await currentUser?.signOut();
    } catch (_) {
      // best-effort
    }
    currentUser = null;
    session = null;
    accessToken = null;
    idToken = null;
    email = null;
  }

  /// Turns a raw Cognito exception into a short, human message for the UI.
  static String friendlyError(Object e) {
    if (!isConfigured) {
      return 'Login isn\'t configured in this build yet.';
    }
    final msg = (e is CognitoClientException ? e.message : e.toString()) ?? e.toString();
    // Log only the Cognito error *class* (never the message, code, email or
    // password) so a delivery/config failure can be told apart from a user
    // typo in the browser console. debugPrint is a no-op in release builds.
    debugPrint('[auth] ${(e is CognitoClientException ? e.code : null) ?? e.runtimeType}');
    if (msg.contains('UsernameExistsException') || msg.contains('already exists')) {
      return 'An account with this email already exists. Try signing in.';
    }
    if (msg.contains('CodeMismatch')) return 'That code is incorrect. Check and try again.';
    if (msg.contains('ExpiredCode')) return 'That code has expired. Tap “Resend code”.';
    if (msg.contains('NotAuthorized')) return 'Incorrect email or password.';
    if (msg.contains('UserNotConfirmed')) return 'Please verify your email first.';
    if (msg.contains('UserNotFound')) return 'Incorrect email or password.'; // uniform message avoids account enumeration
    if (msg.contains('InvalidPassword') || msg.contains('Password did not conform')) {
      return 'Password must be 8+ characters with an uppercase, a lowercase, and a number.';
    }
    if (msg.contains('LimitExceeded') || msg.contains('TooManyRequests') || msg.contains('Attempt limit exceeded')) {
      return 'Too many attempts. Please wait a few minutes and try again.';
    }
    if (msg.contains('CodeDeliveryFailure') || msg.contains('Failed to deliver')) {
      // Cognito could not hand the email to its sender (default sender cap
      // hit, or SES identity/sandbox not set up — see infra/lib/auth-stack.ts).
      return 'We couldn\'t send the email code right now. Try again shortly or contact support.';
    }
    if (msg.contains('InvalidParameter')) {
      return 'Some of the details entered are not valid. Check them and try again.';
    }
    return msg;
  }
}
