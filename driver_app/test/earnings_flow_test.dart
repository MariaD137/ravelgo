import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ravelgo_driver_app/views/auth/login_screen.dart';
import 'package:ravelgo_driver_app/views/earnings/cash_out_screen.dart';
import 'package:ravelgo_driver_app/views/earnings/payout_history_screen.dart';

void main() {
  testWidgets('driver sign in rejects invalid credentials', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));

    await tester.tap(find.text('Sign in').last);
    await tester.pump();
    expect(find.text('Enter a valid email address'), findsOneWidget);
    expect(find.text('Password must be at least 6 characters'), findsOneWidget);
    expect(find.byType(LoginScreen), findsOneWidget);
  });

  // The payout account and history screens read from the backend
  // (POST/GET /api/payouts/*). Without a backend they render their scaffold and
  // a loading/error state - these smoke tests assert they build cleanly.
  testWidgets('payout account screen renders its scaffold', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: CashOutScreen()));
    expect(find.text('Payout account'), findsOneWidget);
  });

  testWidgets('payout history screen renders its scaffold', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: PayoutHistoryScreen()));
    expect(find.text('Payout history'), findsOneWidget);
  });
}
