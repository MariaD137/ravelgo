import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ravelgo_user_app/views/Login/login.dart';
import 'package:ravelgo_user_app/views/Signup/AddPhoto.dart';
import 'package:ravelgo_user_app/views/Signup/CreateAccount.dart';
import 'package:ravelgo_user_app/views/Signup/VerifyAccount.dart';

void main() {
  testWidgets('sign up runs the rider flow and never shows driver onboarding',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: Login()));

    await tester.tap(find.textContaining('Sign up'));
    await tester.pumpAndSettle();

    // Rider account creation - not driver registration.
    expect(find.byType(CreateAccountScreen), findsOneWidget);
    expect(find.text('Create your account'), findsOneWidget);
    expect(find.textContaining('driver', findRichText: true), findsNothing);
    expect(find.textContaining('Driver'), findsNothing);

    await tester.enterText(find.byType(TextFormField).at(0), 'Thelma Ibeh');
    await tester.enterText(find.byType(TextFormField).at(1), 'thelma@example.com');
    await tester.enterText(find.byType(TextFormField).at(2), '08130006677');
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();

    // Verification step.
    expect(find.byType(VerifyAccountScreen), findsOneWidget);
    await tester.enterText(find.byType(TextField), '123456');
    await tester.tap(find.text('Verify'));
    await tester.pumpAndSettle();

    // Rider profile setup - still no driver/vehicle onboarding anywhere.
    expect(find.byType(AddPhotoScreen), findsOneWidget);
    expect(find.text('Set up your profile'), findsOneWidget);
    expect(find.text('Skip for now'), findsOneWidget);
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
