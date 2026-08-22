import 'package:flutter_test/flutter_test.dart';
import 'package:ravelgo_rider_app/services/api/auth_provider.dart';

void main() {
  group('DevOnlyAuthProvider', () {
    test('starts unauthenticated with no token', () async {
      final provider = DevOnlyAuthProvider();

      expect(await provider.isAuthenticated(), isFalse);
      expect(await provider.getAccessToken(), isNull);
    });

    test('setToken() is reflected in isAuthenticated and getAccessToken', () async {
      final provider = DevOnlyAuthProvider();

      provider.setToken('dev-token');

      expect(await provider.isAuthenticated(), isTrue);
      expect(await provider.getAccessToken(), 'dev-token');
    });

    test('logout() clears the token', () async {
      final provider = DevOnlyAuthProvider();
      provider.setToken('dev-token');

      await provider.logout();

      expect(await provider.isAuthenticated(), isFalse);
      expect(await provider.getAccessToken(), isNull);
    });

    test('login() throws UnimplementedError — there is no real Cognito integration yet', () async {
      final provider = DevOnlyAuthProvider();

      await expectLater(
        provider.login(username: 'a', password: 'b'),
        throwsA(isA<UnimplementedError>()),
      );
    });
  });
}
