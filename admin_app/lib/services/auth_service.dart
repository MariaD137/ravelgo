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
  // From the verified ID token's given_name/family_name claims — never
  // fabricated or hard-coded. Null until a session has been applied at
  // least once (fresh sign-in or a restored session).
  static String? name;
  static List<String> groups = const [];

  /// Set by signIn() when Cognito responds with the NEW_PASSWORD_REQUIRED
  /// challenge — every admin created via POST /admin-users starts in this
  /// state until they set their own password once. Consumed by
  /// completeNewPassword().
  static CognitoUser? _pendingNewPasswordUser;

  /// Set by signIn() when Cognito responds with the SOFTWARE_TOKEN_MFA
  /// challenge — an admin who has already enrolled TOTP MFA gets this on
  /// every sign-in. Consumed by submitMfaCode().
  static CognitoUser? _pendingMfaUser;

  static bool get isSignedIn => accessToken != null;

  /// True only when the signed-in Cognito user is in the "Admin" group.
  /// This is a UX convenience only — every backend admin endpoint enforces
  /// requireRole("Admin") independently, so this check can never itself
  /// grant access to anything; it just lets the app reject a non-admin
  /// before showing the dashboard instead of after a confusing 403.
  static bool get isAdmin => groups.contains('Admin');

  /// True only when the app was built with real Cognito settings. Lets the UI
  /// give a clear message instead of a cryptic error if config is missing.
  /// dotenv itself throws if load() was never called (e.g. a widget test
  /// that never runs main()) — caught here so this getter can never itself
  /// become the "cryptic error" it exists to prevent.
  static bool get isConfigured {
    try {
      return (dotenv.env['COGNITO_USER_POOL_ID'] ?? '').isNotEmpty &&
          (dotenv.env['COGNITO_CLIENT_ID'] ?? '').isNotEmpty;
    } catch (_) {
      return false;
    }
  }

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

  static void _applySession(CognitoUser user, CognitoUserSession s) {
    currentUser = user;
    session = s;
    accessToken = s.getAccessToken().getJwtToken();
    idToken = s.getIdToken().getJwtToken();
    final claims = s.getIdToken().decodePayload();
    email = claims['email']?.toString() ?? email;
    final givenName = claims['given_name']?.toString() ?? '';
    final familyName = claims['family_name']?.toString() ?? '';
    final fullName = '$givenName $familyName'.trim();
    if (fullName.isNotEmpty) name = fullName;
    final rawGroups = claims['cognito:groups'];
    groups = rawGroups is List ? rawGroups.map((g) => '$g').toList() : const [];
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

  /// Change the password for the currently signed-in admin.
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

  /// Sign in and persist the resulting tokens (via the pool's storage) for
  /// API calls and across reloads.
  ///
  /// Throws CognitoUserNewPasswordRequiredException for an admin signing in
  /// for the first time with the temporary password Cognito emailed them
  /// (see POST /admin-users) — the caller must show a "set a new password"
  /// step and call completeNewPassword() to finish signing in.
  ///
  /// Throws CognitoUserTotpRequiredException for an admin who has already
  /// enrolled TOTP MFA — the caller must show a 6-digit code entry step and
  /// call submitMfaCode() to finish signing in.
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
    } on CognitoUserNewPasswordRequiredException {
      _pendingNewPasswordUser = user;
      rethrow;
    } on CognitoUserTotpRequiredException {
      _pendingMfaUser = user;
      rethrow;
    }
  }

  /// Completes sign-in after signIn() (or completeNewPassword()) threw
  /// CognitoUserTotpRequiredException, by submitting the 6-digit code from
  /// the admin's authenticator app.
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

  /// Starts TOTP MFA enrollment for the CURRENTLY signed-in admin (called
  /// after a full sign-in with no outstanding challenge — MFA is optional at
  /// the Cognito pool level so this is never itself a login-time challenge;
  /// see infra/lib/auth-stack.ts for why, and the Admin App gates full access
  /// behind having completed this at least once instead). Returns the shared
  /// secret so the caller can render it as a QR code (otpauthUri) or as
  /// manually-typed text.
  static Future<({String secret, String otpauthUri})> beginMfaEnrollment() async {
    final user = currentUser;
    if (user == null) {
      throw CognitoClientException('Please sign in again to set up MFA.');
    }
    final secret = await user.associateSoftwareToken();
    if (secret == null) {
      throw CognitoClientException('Could not start MFA setup. Please try again.');
    }
    final account = Uri.encodeComponent(email ?? 'admin');
    final otpauthUri = 'otpauth://totp/RavelGo%20Admin:$account?secret=$secret&issuer=RavelGo%20Admin';
    return (secret: secret, otpauthUri: otpauthUri);
  }

  /// Verifies the 6-digit code from the admin's authenticator app against
  /// the secret from beginMfaEnrollment(), and — only once verified — makes
  /// TOTP the admin's preferred MFA method so every future sign-in requires
  /// it. Returns false (does not enable MFA) if the code doesn't verify.
  static Future<bool> completeMfaEnrollment({required String code}) async {
    final user = currentUser;
    if (user == null) {
      throw CognitoClientException('Please sign in again to set up MFA.');
    }
    final verified = await user.verifySoftwareToken(totpCode: code, friendlyDeviceName: 'RavelGo Admin App');
    if (!verified) return false;
    await user.setUserMfaPreference(null, IMfaSettings(enabled: true, preferredMfa: true));
    return true;
  }

  /// Completes a first-sign-in password change after signIn() threw
  /// CognitoUserNewPasswordRequiredException. Sets the caller's chosen
  /// password as their real one and finishes signing them in.
  static Future<void> completeNewPassword({required String newPassword}) async {
    final user = _pendingNewPasswordUser;
    if (user == null) {
      throw CognitoClientException('Your session expired — please sign in again.');
    }
    final s = await user.sendNewPasswordRequiredAnswer(newPassword);
    if (s != null) {
      _applySession(user, s);
    }
    _pendingNewPasswordUser = null;
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
    name = null;
    groups = const [];
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
