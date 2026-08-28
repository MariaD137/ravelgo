import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ravelgo_driver_app/models/earnings_state.dart';
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

  testWidgets('cash out validates the amount', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: CashOutScreen()));

    await tester.tap(find.text('Request cash out'));
    await tester.pump();
    expect(find.text('Enter a valid amount'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '999999999');
    await tester.tap(find.text('Request cash out'));
    await tester.pump();
    expect(find.text('Amount exceeds your available balance'), findsOneWidget);
  });

  testWidgets('cash out confirms, records a PENDING payout, and never claims a transfer',
      (WidgetTester tester) async {
    final before = DriverEarningsState.instance.payouts.length;
    final balanceBefore = DriverEarningsState.instance.availableBalance;

    await tester.pumpWidget(const MaterialApp(home: CashOutScreen()));

    await tester.enterText(find.byType(TextField), '5000');
    await tester.tap(find.text('Request cash out'));
    await tester.pumpAndSettle();

    expect(find.text('Confirm cash out'), findsOneWidget);
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();

    // Result screen: request received, pending, explicitly no money moved.
    expect(find.text('Cash-out request received'), findsOneWidget);
    expect(find.textContaining('PENDING'), findsOneWidget);
    expect(find.textContaining('no money has moved'), findsOneWidget);
    expect(find.textContaining('Transfer successful'), findsNothing);

    expect(DriverEarningsState.instance.payouts.length, before + 1);
    expect(DriverEarningsState.instance.payouts.first.status, PayoutStatus.pending);
    expect(DriverEarningsState.instance.availableBalance, balanceBefore - 5000);
  });

  testWidgets('payout history lists payouts with status badges', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: PayoutHistoryScreen()));

    expect(find.textContaining('₦85000'), findsOneWidget);
    expect(find.text('Paid'), findsWidgets);
    // The pending request from the previous test session state also shows.
    expect(find.text('Pending'), findsWidgets);
  });
}
