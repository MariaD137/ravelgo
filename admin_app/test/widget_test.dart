import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ravelgo_admin/services/api/auth_provider.dart';
import 'package:ravelgo_admin/theme/app_theme.dart';
import 'package:ravelgo_admin/views/auth/admin_login_screen.dart';
import 'package:ravelgo_admin/views/splash/splash_screen.dart';

void main() {
  testWidgets('primary button renders with given label', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppComponents.primaryButton(text: 'Approve', onPressed: () {}),
        ),
      ),
    );

    expect(find.text('Approve'), findsOneWidget);
  });

  testWidgets('splash screen navigates to admin login after its timer', (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(home: SplashScreen(authProvider: DevOnlyAuthProvider.instance)));
    expect(find.byType(SplashScreen), findsOneWidget);

    // Flush the navigation Timer and let the route transition settle. An
    // uncancelled Future.delayed here used to fail this test with "A Timer
    // is still pending even after the widget tree was disposed."
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.byType(AdminLoginScreen), findsOneWidget);
  });

  testWidgets('splash screen disposed before its timer fires does not throw', (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(home: SplashScreen(authProvider: DevOnlyAuthProvider.instance)));
    // Replace the tree before the 2-second timer fires — dispose() must
    // cancel it; otherwise the callback runs against a deactivated context.
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Text('elsewhere'))));
    await tester.pump(const Duration(seconds: 3));
    expect(tester.takeException(), isNull);
  });
}
