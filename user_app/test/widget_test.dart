import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ravelgo_user_app/main.dart';
import 'package:ravelgo_user_app/views/SplashScreen/SplashScreen.dart';
import 'package:ravelgo_user_app/views/Login/login.dart';

void main() {
  testWidgets('app boots to the splash screen, then navigates to Login', (WidgetTester tester) async {
    await tester.pumpWidget(MyApp());
    expect(find.byType(SplashScreen), findsOneWidget);

    // SplashScreen schedules a 5-second Future.delayed that navigates to
    // Login. Advance the test clock past it so the timer fires and
    // completes within this test instead of leaking into the next one.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.byType(Login), findsOneWidget);
  });
}
