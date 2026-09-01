import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ravelgo_user_app/views/Signup/CreateAccount.dart';
import 'package:ravelgo_user_app/views/Signup/VerifyAccount.dart';

void main() {
  testWidgets('account creation is rider-only — never shows driver onboarding',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: CreateAccountScreen()));

    // Rider account creation - not driver registration.
    expect(find.text('Create your account'), findsOneWidget);
    expect(find.textContaining('driver', findRichText: true), findsNothing);
    expect(find.textContaining('Driver'), findsNothing);
    // No driver/vehicle onboarding fields anywhere on the rider signup.
    expect(find.textContaining('license'), findsNothing);
    expect(find.textContaining('Vehicle'), findsNothing);
  });

  testWidgets('signup rejects invalid input', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: CreateAccountScreen()));

    await tester.tap(find.text('Create account'));
    await tester.pump();

    expect(find.text('Enter your name'), findsOneWidget);
    expect(find.text('Enter a valid email address'), findsOneWidget);
    expect(find.text('Enter a valid phone number'), findsOneWidget);
    expect(find.text('You must accept the Terms & Conditions'), findsOneWidget);
    // Still on the signup screen - no navigation happened.
    expect(find.byType(CreateAccountScreen), findsOneWidget);
  });

  testWidgets('verification rejects a short code', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: VerifyAccountScreen()));

    await tester.enterText(find.byType(TextField), '12');
    await tester.tap(find.text('Verify'));
    await tester.pump();

    expect(find.text('Enter the 6-digit code'), findsOneWidget);
    expect(find.byType(VerifyAccountScreen), findsOneWidget);
  });
}
