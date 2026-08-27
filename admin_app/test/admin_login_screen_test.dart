import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ravelgo_admin/views/auth/admin_login_screen.dart';

// AuthService talks to Cognito over a real dart:io HttpClient with no
// injection point (same constraint noted in driver_app's
// forgot_password_screen_test.dart / verify_account_screen_test.dart).
// This file is scoped to what's genuinely verifiable without a network
// call: the empty-field guard that returns before AuthService is ever
// invoked. It does not exercise sign-in, the Cognito-group check, or the
// "not authorized for RavelGo Admin" rejection path itself — all three
// require a real Cognito user pool, exactly as noted in the audit report
// (AWS staging dependency).
void main() {
  testWidgets('renders a work-email field, a password field, and a sign-in button', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: AdminLoginScreen()));

    expect(find.byType(TextField), findsNWidgets(2));
    expect(find.text('Sign in'), findsOneWidget);
  });

  testWidgets('shows a validation error for empty credentials instead of calling Cognito', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: AdminLoginScreen()));

    await tester.tap(find.text('Sign in'));
    await tester.pump();

    expect(find.text('Please enter your email and password'), findsOneWidget);
    // Still on the login screen — never navigated to AdminShell.
    expect(find.text('Sign in'), findsOneWidget);
  });

  testWidgets('the access-restriction notice is visible on first load', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: AdminLoginScreen()));

    expect(find.text('Access is restricted to authorized RavelGo staff.'), findsOneWidget);
  });
}
