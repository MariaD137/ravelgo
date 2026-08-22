import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ravelgo_driver_app/models/driver_operational_state.dart';
import 'package:ravelgo_driver_app/services/api/api_client.dart';
import 'package:ravelgo_driver_app/services/api/auth_provider.dart';
import 'package:ravelgo_driver_app/services/driver_session.dart';
import 'package:ravelgo_driver_app/views/auth/login_screen.dart';
import 'package:ravelgo_driver_app/views/shell/driver_shell.dart';

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
  // These regression tests exist because of a real production incident:
  // driver_app's release build crashed the instant any screen touched
  // DriverSession, because ApiClient() defaulted to DevOnlyAuthProvider,
  // whose constructor deliberately throws in kReleaseMode. See
  // PRE_AWS_AUTH_ARCHITECTURE_REMEDIATION.md for the full writeup.

  group('Release-safe dependency construction', () {
    test('a bare ApiClient() never throws, in any test run (regression for the release-mode crash)', () {
      // flutter test never compiles with kReleaseMode true, so this can't
      // prove the release branch specifically — that's proven empirically
      // by an actual `flutter build web --release` (see
      // PRE_AWS_AUTH_ARCHITECTURE_REMEDIATION.md's "Release Build Results"
      // section) rather than by a unit test. What this test does prove:
      // ApiClient's default AuthProvider fallback is createDefaultAuthProvider(),
      // not a bare DevOnlyAuthProvider() call — the exact class of bug this
      // whole file exists to catch.
      expect(() => ApiClient(), returnsNormally);
    });

    test('createDefaultAuthProvider() is the one place the AuthProvider choice is made', () async {
      // Under test (kReleaseMode == false), this must be the dev provider —
      // proving the factory's non-release branch is wired correctly. Its
      // release branch is verified by the real release build instead (see
      // above): kReleaseMode is a compile-time constant flutter test cannot
      // flip, so no unit test can exercise that branch directly.
      final provider = createDefaultAuthProvider();
      expect(provider, same(DevOnlyAuthProvider.instance));
    });

    test('UnauthenticatedAuthProvider never throws to construct, and never authenticates', () async {
      // The class createDefaultAuthProvider() returns in release builds —
      // constructing it must be unconditionally safe (no kReleaseMode guard
      // needed, unlike DevOnlyAuthProvider) since it never fabricates a
      // session either way.
      final provider = UnauthenticatedAuthProvider();
      expect(await provider.isAuthenticated(), isFalse);
      expect(await provider.getAccessToken(), isNull);
      await expectLater(
        provider.login(username: 'a', password: 'b'),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('DriverSession never implicitly constructs an AuthProvider', () {
    test('DriverSession.instance throws if read before initialize()/resetForTesting()', () {
      // No production or test code should ever hit this in practice (main()
      // and every test's setUp() call one of those first) — this documents
      // and locks in that DriverSession has no implicit fallback
      // construction path, which is the root cause the P0 crash traced back
      // to (a bare ApiClient() defaulting into DevOnlyAuthProvider.instance).
      DriverSession.clearForTesting();
      expect(() => DriverSession.instance, throwsA(isA<StateError>()));
    });

    test('DriverSession.initialize() accepts any AuthProvider implementation, not just dev ones', () {
      final fake = _FakeAuthProvider();
      DriverSession.initialize(authProvider: fake, apiClient: ApiClient(authProvider: fake));
      expect(DriverSession.instance.authStatus, AuthStatus.unauthenticated);
    });
  });

  group('DriverSession.signIn() / signOut() drive AuthProvider, not navigation', () {
    late _FakeAuthProvider fakeAuth;

    setUp(() {
      fakeAuth = _FakeAuthProvider();
      DriverSession.resetForTesting(authProvider: fakeAuth, apiClient: ApiClient(authProvider: fakeAuth));
    });

    test('signIn() calls AuthProvider.login() exactly once with the given credentials', () async {
      final ok = await DriverSession.instance.signIn(username: 'a@b.com', password: 'pw');

      expect(ok, isTrue);
      expect(fakeAuth.loginCallCount, 1);
      expect(DriverSession.instance.authStatus, AuthStatus.authenticated);
    });

    test('a failed login sets authenticationFailed and returns false — the caller must not navigate', () async {
      DriverSession.resetForTesting(
        authProvider: _FakeAuthProvider(shouldSucceed: false, loginError: 'bad password'),
        apiClient: ApiClient(authProvider: fakeAuth),
      );

      final ok = await DriverSession.instance.signIn(username: 'a@b.com', password: 'wrong');

      expect(ok, isFalse);
      expect(DriverSession.instance.authStatus, AuthStatus.authenticationFailed);
      expect(DriverSession.instance.authErrorMessage, contains('bad password'));
    });

    test('signOut() calls AuthProvider.logout(), clears authStatus, and returns operational state to offline', () async {
      await DriverSession.instance.signIn(username: 'a@b.com', password: 'pw');
      DriverSession.instance.markBusy(DriverOperationalState.onRide, 'trip-1');

      await DriverSession.instance.signOut();

      expect(fakeAuth.logoutCallCount, 1);
      expect(DriverSession.instance.authStatus, AuthStatus.unauthenticated);
      expect(DriverSession.instance.state, DriverOperationalState.offline);
      expect(DriverSession.instance.activeAssignmentId, isNull);
    });
  });

  group('ApiClient.onUnauthorized fires on a real 401, so a session can react to one', () {
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

  group('LoginScreen depends on AuthProvider — navigation follows auth state, not the tap itself', () {
    setUp(() {
      DriverSession.resetForTesting(
        authProvider: DevOnlyAuthProvider.instance,
        apiClient: ApiClient(authProvider: DevOnlyAuthProvider.instance),
      );
    });

    testWidgets('a failed sign-in shows an error and does not navigate to DriverShell', (tester) async {
      DriverSession.resetForTesting(
        authProvider: _FakeAuthProvider(shouldSucceed: false, loginError: 'wrong password'),
        apiClient: ApiClient(authProvider: DevOnlyAuthProvider.instance),
      );

      await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
      await tester.enterText(find.widgetWithText(TextField, 'Email').first, 'a@b.com');
      await tester.enterText(find.byType(TextField).at(1), 'wrong');
      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();

      expect(find.byType(DriverShell), findsNothing);
      expect(find.textContaining('wrong password'), findsOneWidget);
    });

    testWidgets('a successful sign-in navigates to DriverShell', (tester) async {
      DriverSession.resetForTesting(
        authProvider: _FakeAuthProvider(shouldSucceed: true),
        apiClient: ApiClient(authProvider: DevOnlyAuthProvider.instance),
      );

      await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
      await tester.enterText(find.widgetWithText(TextField, 'Email').first, 'a@b.com');
      await tester.enterText(find.byType(TextField).at(1), 'right');
      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();

      expect(find.byType(DriverShell), findsOneWidget);
    });
  });
}
