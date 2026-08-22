import 'package:flutter_test/flutter_test.dart';
import 'package:ravelgo_driver_app/services/api/auth_provider.dart';

void main() {
  group('DevOnlyAuthProvider', () {
    test('starts unauthenticated with no token', () async {
      final provider = DevOnlyAuthProvider();
      expect(await provider.isAuthenticated(), isFalse);
      expect(await provider.getAccessToken(), isNull);
    });

    test('setToken() makes isAuthenticated/getAccessToken reflect it', () async {
      final provider = DevOnlyAuthProvider();
      provider.setToken('dev-token-123');

      expect(await provider.isAuthenticated(), isTrue);
      expect(await provider.getAccessToken(), 'dev-token-123');
    });

    test('logout() clears the token', () async {
      final provider = DevOnlyAuthProvider();
      provider.setToken('dev-token-123');

      await provider.logout();

      expect(await provider.isAuthenticated(), isFalse);
      expect(await provider.getAccessToken(), isNull);
    });

    test('login() fails loudly rather than fabricating a session (no real Cognito integration exists yet)', () async {
      final provider = DevOnlyAuthProvider();

      await expectLater(
        provider.login(username: 'someone@example.com', password: 'whatever'),
        throwsA(isA<UnimplementedError>()),
      );
      expect(await provider.isAuthenticated(), isFalse);
    });
  });
}
