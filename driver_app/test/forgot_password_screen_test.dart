import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ravelgo_driver_app/views/auth/forgot_password_screen.dart';

// AuthService talks to Cognito over a real dart:io HttpClient with no
// injection point (unlike DriverApi/AdminApi, which do support a mock
// client — see vehicle_list_screen_test.dart for that pattern). These
// tests are therefore scoped to what's genuinely verifiable without a
// network call: the client-side validation guards in
// ForgotPasswordScreen, which return before AuthService is ever invoked.
// They do not exercise forgotPassword()/confirmForgotPassword() themselves
// — that requires a real Cognito user pool, exactly as noted in the audit
// report (AWS staging dependency).
void main() {
  testWidgets('starts on the email step', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: ForgotPasswordScreen()));

    expect(find.text('Send reset code'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget); // just the email field
  });

  testWidgets('shows a validation error for an empty email instead of calling Cognito', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: ForgotPasswordScreen()));

    await tester.tap(find.text('Send reset code'));
    await tester.pump();

    expect(find.text('Please enter your email'), findsOneWidget);
    // Still on the email step — never advanced past client-side validation.
    expect(find.text('Send reset code'), findsOneWidget);
  });

  testWidgets('code step is not reachable without a successful code request', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: ForgotPasswordScreen()));

    // The code+password fields only exist once _codeRequested is true,
    // which only happens after AuthService().forgotPassword() returns
    // success — never reachable in a widget test with no real Cognito.
    expect(find.text('Reset code'), findsNothing);
    expect(find.text('New password'), findsNothing);
  });
}
