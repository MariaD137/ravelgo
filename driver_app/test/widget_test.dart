import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ravelgo_driver_app/services/api/api_client.dart';
import 'package:ravelgo_driver_app/services/api/auth_provider.dart';
import 'package:ravelgo_driver_app/services/driver_session.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';
import 'package:ravelgo_driver_app/views/auth/login_screen.dart';
import 'package:ravelgo_driver_app/views/splash/splash_screen.dart';

void main() {
  // LoginScreen (reached via the splash-navigation test below) reads
  // DriverSession.instance to render its auth state — main.dart's
  // composition root normally sets this up before runApp(); tests stand in
  // for that with a DevOnlyAuthProvider.
  setUp(() {
    DriverSession.resetForTesting(
      authProvider: DevOnlyAuthProvider.instance,
      apiClient: ApiClient(authProvider: DevOnlyAuthProvider.instance),
    );
  });

  testWidgets('primary button renders with given label', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppComponents.primaryButton(text: 'Go online', onPressed: () {}),
        ),
      ),
    );

    expect(find.text('Go online'), findsOneWidget);
  });

  testWidgets('splash screen navigates to login after its timer, and cancels cleanly on early dispose', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: SplashScreen()));
    expect(find.byType(SplashScreen), findsOneWidget);

    // Flush the navigation Timer and let the route transition settle. An
    // uncancelled Future.delayed here used to fail this test with "A Timer
    // is still pending even after the widget tree was disposed."
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);
  });

  testWidgets('splash screen disposed before its timer fires does not throw', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: SplashScreen()));
    // Replace the tree before the 3-second timer fires — dispose() must
    // cancel it; otherwise the callback runs against a deactivated context.
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Text('elsewhere'))));
    await tester.pump(const Duration(seconds: 4));
    expect(tester.takeException(), isNull);
  });
}
