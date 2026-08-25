import 'dart:convert';
import 'dart:io';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:ravelgo_admin/utils/jwt.dart';

class AuthService {
  static final AuthService _instance = AuthService._();
  factory AuthService() => _instance;
  AuthService._();

  final _storage = const FlutterSecureStorage();
  static const _accessTokenKey = 'access_token';
  static const _refreshTokenKey = 'refresh_token';
  static const _idTokenKey = 'id_token';

  String get _cognitoUrl {
    final region = dotenv.env['AWS_REGION'] ?? 'us-east-1';
    return 'https://cognito-idp.$region.amazonaws.com';
  }

  String get _clientId => dotenv.env['COGNITO_CLIENT_ID'] ?? '';

  Future<String?> getAccessToken() async {
    return _storage.read(key: _accessTokenKey);
  }

  /// Decodes the stored access token's JWT payload — the same token and
  /// the same `cognito:groups` claim the backend's own verifier reads from
  /// (see backend/src/middleware/auth.ts). This is never a security
  /// boundary: it's not signature-verified here, and the backend enforces
  /// requireRole("Admin") independently on every request regardless of
  /// what this returns. It only decides what the UI shows before the
  /// first API call would otherwise reveal a 403.
  Future<Map<String, dynamic>?> _decodedAccessTokenPayload() async {
    final token = await getAccessToken();
    if (token == null) return null;
    return decodeJwtPayload(token);
  }

  Future<bool> isLoggedIn() async {
    final payload = await _decodedAccessTokenPayload();
    if (payload == null) return false;
    final exp = payload['exp'] as int?;
    if (exp == null) return false;
    return DateTime.fromMillisecondsSinceEpoch(exp * 1000).isAfter(DateTime.now());
  }

  /// The Cognito groups on the currently stored access token, or an empty
  /// list if there's no session or the token doesn't carry the claim.
  Future<List<String>> getCognitoGroups() async {
    final payload = await _decodedAccessTokenPayload();
    final groups = payload?['cognito:groups'];
    if (groups is List) return groups.map((g) => g.toString()).toList();
    return const [];
  }

  /// Whether the signed-in user's own access token carries the given
  /// Cognito group. See _decodedAccessTokenPayload's doc comment — this is
  /// a UI-only convenience, not the real authorization check.
  Future<bool> isInGroup(String group) async {
    final groups = await getCognitoGroups();
    return groups.contains(group);
  }

  Future<Map<String, dynamic>> signIn(String email, String password) async {
    final http = HttpClient();
    final uri = Uri.parse(_cognitoUrl);
    final request = await http.postUrl(uri);
    request.headers.set('Content-Type', 'application/x-amz-json-1.1');
    request.headers.set('X-Amz-Target', 'AWSCognitoIdentityProviderService.InitiateAuth');
    request.write(jsonEncode({
      'AuthFlow': 'USER_PASSWORD_AUTH',
      'ClientId': _clientId,
      'AuthParameters': {
        'USERNAME': email,
        'PASSWORD': password,
      },
    }));
    final response = await request.close();
    final body = jsonDecode(await response.transform(utf8.decoder).join());

    if (response.statusCode != 200) {
      final errorType = body['__type'] ?? 'UnknownError';
      final message = body['message'] ?? 'Sign in failed';
      return {'success': false, 'error': _friendlyError(errorType, message)};
    }

    final result = body['AuthenticationResult'];
    await _storage.write(key: _accessTokenKey, value: result['AccessToken']);
    await _storage.write(key: _refreshTokenKey, value: result['RefreshToken']);
    await _storage.write(key: _idTokenKey, value: result['IdToken']);
    return {'success': true};
  }

  Future<bool> refreshSession() async {
    final refreshToken = await _storage.read(key: _refreshTokenKey);
    if (refreshToken == null) return false;

    final http = HttpClient();
    final uri = Uri.parse(_cognitoUrl);
    final request = await http.postUrl(uri);
    request.headers.set('Content-Type', 'application/x-amz-json-1.1');
    request.headers.set('X-Amz-Target', 'AWSCognitoIdentityProviderService.InitiateAuth');
    request.write(jsonEncode({
      'AuthFlow': 'REFRESH_TOKEN_AUTH',
      'ClientId': _clientId,
      'AuthParameters': {
        'REFRESH_TOKEN': refreshToken,
      },
    }));
    final response = await request.close();
    if (response.statusCode != 200) return false;

    final body = jsonDecode(await response.transform(utf8.decoder).join());
    final result = body['AuthenticationResult'];
    await _storage.write(key: _accessTokenKey, value: result['AccessToken']);
    if (result['IdToken'] != null) {
      await _storage.write(key: _idTokenKey, value: result['IdToken']);
    }
    return true;
  }

  Future<void> signOut() async {
    await _storage.deleteAll();
  }

  String _friendlyError(String type, String message) {
    switch (type) {
      case 'NotAuthorizedException':
        return 'Incorrect email or password';
      case 'UserNotFoundException':
        return 'No account found with this email';
      case 'UserNotConfirmedException':
        return 'Please verify your email before signing in';
      default:
        return message;
    }
  }
}
