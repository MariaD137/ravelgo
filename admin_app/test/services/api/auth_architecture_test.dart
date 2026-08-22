import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ravelgo_admin/services/api/api_client.dart';
import 'package:ravelgo_admin/services/api/auth_provider.dart';
import 'package:ravelgo_admin/views/auth/admin_login_screen.dart';
import 'package:ravelgo_admin/views/shell/admin_shell.dart';

/// A controllable double, not [DevOnlyAuthProvider] and not
/// [UnauthenticatedAuthProvider] — lets tests choose exactly when [login]
/// succeeds or fails without depending on either production implementation.
class _FakeAuthProvider implements AuthProvider {
  _FakeAuthProvider({this.shouldSucceed = true, this.loginError = 'invalid credentials'});

  final bool shouldSucceed;
  final String loginError;
  String? _token;
  int loginCallCount = 0;
  int logoutCallCount = 0;

  @override
  Future<void> login({required String username, required String password}) async {
    loginCallCount++;
    if (!shouldSucceed) throw StateError(loginError);
    _token = 'fake-token-for-$username';
  }

  @override
  Future<void> logout() async {
    logoutCallCount++;
    _token = null;
  }

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
  // in kReleaseMode. admin_app's AdminLoginScreen had the same underlying
  // flaw (navigating in on tap without ever calling AuthProvider), fixed
  // here. See PRE_AWS_AUTH_ARCHITECTURE_REMEDIATION.md for the full writeup.

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

  group('AdminLoginScreen depends on AuthProvider — navigation follows auth state, not the tap itself', () {
    testWidgets('a failed sign-in shows an error and does not navigate to AdminShell', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: AdminLoginScreen(authProvider: _FakeAuthProvider(shouldSucceed: false, loginError: 'wrong password')),
      ));
      await tester.enterText(find.widgetWithText(TextField, 'Work email').first, 'a@b.com');
      await tester.enterText(find.byType(TextField).at(1), 'wrong');
      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();

      expect(find.byType(AdminShell), findsNothing);
      expect(find.textContaining('wrong password'), findsOneWidget);
    });

    testWidgets('a successful sign-in navigates to AdminShell', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: AdminLoginScreen(authProvider: _FakeAuthProvider(shouldSucceed: true)),
      ));
      await tester.enterText(find.widgetWithText(TextField, 'Work email').first, 'a@b.com');
      await tester.enterText(find.byType(TextField).at(1), 'right');
      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();

      expect(find.byType(AdminShell), findsOneWidget);
    });
  });

  group('AdminShell logout drives AuthProvider, not just navigation', () {
    testWidgets('tapping "Log out" in the side menu calls AuthProvider.logout() and returns to AdminLoginScreen', (tester) async {
      final fakeAuth = _FakeAuthProvider(shouldSucceed: true);
      await tester.pumpWidget(MaterialApp(home: AdminShell(authProvider: fakeAuth)));

      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();

      // "Log out" is the last item in a long drawer ListView — off-screen
      // (and so not yet built) until scrolled into view. dragUntilVisible
      // gets it built and partially on-screen; ensureVisible then scrolls
      // it precisely into the viewport so the tap actually lands on it.
      final logOutFinder = find.text('Log out');
      await tester.dragUntilVisible(
        logOutFinder,
        find.descendant(of: find.byType(Drawer), matching: find.byType(ListView)),
        const Offset(0, -100),
      );
      await tester.ensureVisible(logOutFinder);
      await tester.pumpAndSettle();
      await tester.tap(logOutFinder);
      await tester.pumpAndSettle();

      expect(fakeAuth.logoutCallCount, 1);
      expect(find.byType(AdminLoginScreen), findsOneWidget);
    });
  });
}
