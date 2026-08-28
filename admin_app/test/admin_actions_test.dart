import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ravelgo_admin/models/admin_actions_state.dart';
import 'package:ravelgo_admin/models/trip_record.dart';
import 'package:ravelgo_admin/views/auth/admin_login_screen.dart';
import 'package:ravelgo_admin/views/carpaddy/car_paddy_requests_screen.dart';
import 'package:ravelgo_admin/views/rentals/rental_listings_screen.dart';
import 'package:ravelgo_admin/views/safety/fraud_alerts_screen.dart';
import 'package:ravelgo_admin/views/trips/trip_admin_detail_screen.dart';

void main() {
  setUp(() {
    final s = AdminActionsState.instance;
    s.refundRequestedTrips.clear();
    s.resolvedTrips.clear();
    s.flaggedTrips.clear();
    s.rentalDecisions.clear();
    s.carPaddyDecisions.clear();
    s.fraudDecisions.clear();
    s.resolvedEmergencies.clear();
  });

  testWidgets('admin sign in rejects invalid credentials', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: AdminLoginScreen()));

    await tester.tap(find.text('Sign in').last);
    await tester.pump();
    expect(find.text('Enter a valid email address'), findsOneWidget);
    expect(find.text('Password must be at least 8 characters'), findsOneWidget);
    expect(find.byType(AdminLoginScreen), findsOneWidget);
  });

  testWidgets('refund confirms and records REQUESTED without claiming success',
      (WidgetTester tester) async {
    final disputed =
        mockTripRecords.firstWhere((t) => t.status == TripRecordStatus.disputed);
    await tester.pumpWidget(MaterialApp(home: TripAdminDetailScreen(trip: disputed)));

    await tester.tap(find.text('Refund rider'));
    await tester.pumpAndSettle();
    expect(find.text('Refund rider?'), findsOneWidget);

    await tester.tap(find.text('Request refund'));
    await tester.pumpAndSettle();

    expect(AdminActionsState.instance.refundRequestedTrips.contains(disputed.id), isTrue);
    expect(find.textContaining('Refund REQUESTED'), findsOneWidget);
    expect(find.textContaining('Refund successful'), findsNothing);
    // Button disabled to prevent duplicate refunds.
    expect(find.text('Refund requested'), findsOneWidget);
  });

  testWidgets('flagging a completed trip requires confirmation and updates the UI',
      (WidgetTester tester) async {
    final completed =
        mockTripRecords.firstWhere((t) => t.status == TripRecordStatus.completed);
    await tester.pumpWidget(MaterialApp(home: TripAdminDetailScreen(trip: completed)));

    await tester.tap(find.text('Flag this trip for review'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Flag trip'));
    await tester.pumpAndSettle();

    expect(AdminActionsState.instance.flaggedTrips.contains(completed.id), isTrue);
    expect(find.textContaining('flagged for review by an administrator'), findsOneWidget);
  });

  testWidgets('rental approval confirms and flips the status badge',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: RentalListingsScreen()));

    expect(find.text('Pending approval'), findsOneWidget);
    await tester.tap(find.text('Approve').first);
    await tester.pumpAndSettle();
    expect(find.text('Approve listing?'), findsOneWidget);
    await tester.tap(find.text('Approve').last);
    await tester.pumpAndSettle();

    expect(find.text('Pending approval'), findsNothing);
    expect(find.text('Approved'), findsNWidgets(2)); // original + newly approved
  });

  testWidgets('car paddy rejection confirms and shows the decided badge',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: CarPaddyRequestsScreen()));

    await tester.tap(find.byIcon(Icons.close).first);
    await tester.pumpAndSettle();
    expect(find.text('Reject request?'), findsOneWidget);
    await tester.tap(find.text('Reject').last);
    await tester.pumpAndSettle();

    expect(find.text('Rejected'), findsNWidgets(2)); // original + newly rejected
    expect(find.byIcon(Icons.close), findsNothing);
  });

  testWidgets('fraud alerts can be dismissed and investigated', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: FraudAlertsScreen()));

    await tester.tap(find.text('Dismiss').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dismiss').last);
    await tester.pumpAndSettle();
    expect(find.text('Dismissed'), findsOneWidget);

    await tester.tap(find.text('Investigate').first);
    await tester.pumpAndSettle();
    expect(find.text('Under investigation'), findsOneWidget);
  });
}
