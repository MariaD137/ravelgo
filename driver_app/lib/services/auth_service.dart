import 'package:amazon_cognito_identity_dart_2/cognito.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Real authentication against the RavelGo Cognito user pool.
///
/// Reads the pool + client IDs from the environment (.env, produced at build
/// time from the deployed Auth stack). Sign-up sends a real 6-digit code to
/// the user's email; confirmation and sign-in return Cognito tokens that the
/// app attaches to backend API calls.
class AuthService {
  static final CognitoUserPool _pool = CognitoUserPool(
    dotenv.env['COGNITO_USER_POOL_ID'] ?? '',
    dotenv.env['COGNITO_CLIENT_ID'] ?? '',
  );

  static CognitoUserSession? session;
  static String? accessToken;
  static String? idToken;
  static String? email;
  static String? givenName;
  static String? familyName;

  static bool get isSignedIn => accessToken != null;

  /// The access token the API client sends as a Bearer credential (valid ~1h).
  static Future<String?> validAccessToken() async => accessToken;

  /// True only when the app was built with real Cognito settings. Lets the UI
  /// give a clear message instead of a cryptic error if config is missing.
  static bool get isConfigured =>
      (dotenv.env['COGNITO_USER_POOL_ID'] ?? '').isNotEmpty &&
      (dotenv.env['COGNITO_CLIENT_ID'] ?? '').isNotEmpty;

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

  /// Sign in and keep the resulting tokens for API calls.
  static Future<void> signIn({required String email, required String password}) async {
    final user = CognitoUser(email, _pool);
    final s = await user.authenticateUser(
      AuthenticationDetails(username: email, password: password),
    );
    session = s;
    accessToken = s?.getAccessToken().getJwtToken();
    idToken = s?.getIdToken().getJwtToken();
    AuthService.email = email;
    final claims = s?.getIdToken().decodePayload();
    if (claims != null) {
      givenName = claims['given_name']?.toString();
      familyName = claims['family_name']?.toString();
      AuthService.email = claims['email']?.toString() ?? email;
    }
  }

  static void signOut() {
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
    if (msg.contains('UsernameExistsException') || msg.contains('already exists')) {
      return 'An account with this email already exists. Try signing in.';
    }
    if (msg.contains('CodeMismatch')) return 'That code is incorrect. Check and try again.';
    if (msg.contains('ExpiredCode')) return 'That code has expired. Tap “Resend code”.';
    if (msg.contains('NotAuthorized')) return 'Incorrect email or password.';
    if (msg.contains('UserNotConfirmed')) return 'Please verify your email first.';
    if (msg.contains('UserNotFound')) return 'No account found for this email.';
    if (msg.contains('InvalidPassword') || msg.contains('Password did not conform')) {
      return 'Password must be 8+ characters with an uppercase, a lowercase, and a number.';
    }
    return msg;
  }
}
