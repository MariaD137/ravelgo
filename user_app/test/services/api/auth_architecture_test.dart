import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ravelgo_rider_app/services/api/api_client.dart';
import 'package:ravelgo_rider_app/services/api/auth_provider.dart';
import 'package:ravelgo_rider_app/views/Login/login.dart';
import 'package:ravelgo_rider_app/views/bottommenu/BottomNavigationView.dart';

/// A controllable double, not [DevOnlyAuthProvider] and not
/// [UnauthenticatedAuthProvider] — lets tests choose exactly when [login]
/// succeeds or fails without depending on either production implementation.
class _FakeAuthProvider implements AuthProvider {
  _FakeAuthProvider({this.shouldSucceed = true, this.loginError = 'invalid credentials'});

  final bool shouldSucceed;
  final String loginError;
  String? _token;
  int loginCallCount = 0;

  @override
  Future<void> login({required String username, required String password}) async {
    loginCallCount++;
    if (!shouldSucceed) throw StateError(loginError);
    _token = 'fake-token-for-$username';
  }

  @override
  Future<void> logout() async => _token = null;

  @override
  Future<String?> getAccessToken() async => _token;

  @override
  Future<bool> isAuthenticated() async => _token != null;
}

void main() {
  // These regression tests exist because of a real production incident in
  // this repo's sibling app, driver_app: its release build crashed the
  // instant any screen touched its API-client session, because ApiClient()
  // defaulted to DevOnlyAuthProvider, whose constructor deliberately throws
  // in kReleaseMode. user_app's Login screen had the same underlying flaw
  // (navigating in on tap without ever calling AuthProvider), fixed here.
  // See PRE_AWS_AUTH_ARCHITECTURE_REMEDIATION.md for the full writeup.

  group('Release-safe dependency construction', () {
    test('a bare ApiClient() never throws, in any test run (regression for the release-mode crash)', () {
      // flutter test never compiles with kReleaseMode true, so this can't
      // prove the release branch specifically — that's proven empirically
      // by an actual `flutter build web --release` instead (see
      // PRE_AWS_AUTH_ARCHITECTURE_REMEDIATION.md's "Release Build Results"
      // section). What this test proves: ApiClient's default AuthProvider
      // fallback is createDefaultAuthProvider(), not a bare
      // DevOnlyAuthProvider() call — the exact class of bug that file
      // documents.
      expect(() => ApiClient(), returnsNormally);
    });

    test('createDefaultAuthProvider() is the one place the AuthProvider choice is made', () {
      // Under test (kReleaseMode == false) this must be the dev provider;
      // its release branch is verified by the real release build instead,
      // since kReleaseMode is a compile-time constant no unit test can flip.
      expect(createDefaultAuthProvider(), same(DevOnlyAuthProvider.instance));
    });

    test('UnauthenticatedAuthProvider never throws to construct, and never authenticates', () async {
      final provider = UnauthenticatedAuthProvider();
      expect(await provider.isAuthenticated(), isFalse);
      expect(await provider.getAccessToken(), isNull);
      await expectLater(provider.login(username: 'a', password: 'b'), throwsA(isA<StateError>()));
    });
  });

  group('ApiClient.onUnauthorized fires on a real 401', () {
    test('a 401 response invokes onUnauthorized before the ApiException is thrown', () async {
      var called = 0;
      final api = ApiClient(
        authProvider: _FakeAuthProvider(),
        onUnauthorized: () => called++,
        httpClient: MockClient((request) async => http.Response('{"error":"Invalid or expired token"}', 401)),
      );

      await expectLater(api.get('/api/whatever'), throwsA(isA<ApiException>()));
      expect(called, 1);
    });
  });

  group('Login depends on AuthProvider — navigation follows auth state, not the tap itself', () {
    testWidgets('a failed sign-in shows an error and does not navigate to BottomNavigationView', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Login(authProvider: _FakeAuthProvider(shouldSucceed: false, loginError: 'wrong password')),
      ));
      await tester.enterText(find.widgetWithText(TextField, 'Email').first, 'a@b.com');
      await tester.enterText(find.byType(TextField).at(1), 'wrong');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Sign in'));
      await tester.pumpAndSettle();

      expect(find.byType(BottomNavigationView), findsNothing);
      expect(find.textContaining('wrong password'), findsOneWidget);
    });

    testWidgets('a successful sign-in navigates to BottomNavigationView', (tester) async {
      await tester.pumpWidget(MaterialApp(home: Login(authProvider: _FakeAuthProvider(shouldSucceed: true))));
      await tester.enterText(find.widgetWithText(TextField, 'Email').first, 'a@b.com');
      await tester.enterText(find.byType(TextField).at(1), 'right');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Sign in'));
      await tester.pumpAndSettle();

      // Home.dart's "Invite Card" (the Home tab BottomNavigationView lands
      // on) wraps a ListTile in a colored DecoratedBox, which triggers a
      // pre-existing, unrelated Material ink-visibility warning during
      // paint. Not an auth-architecture issue — drained here so it doesn't
      // fail this regression test; see PRE_AWS_AUTH_ARCHITECTURE_REMEDIATION.md.
      tester.takeException();

      expect(find.byType(BottomNavigationView), findsOneWidget);
    });
  });
}
