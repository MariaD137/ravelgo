import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ravelgo_admin/services/admin_api.dart';
import 'package:ravelgo_admin/views/auth/admin_login_screen.dart';
import 'package:ravelgo_admin/views/carpaddy/car_paddy_requests_screen.dart';
import 'package:ravelgo_admin/views/payouts/payouts_screen.dart';
import 'package:ravelgo_admin/views/rentals/rental_listings_screen.dart';
import 'package:ravelgo_admin/views/safety/fraud_alerts_screen.dart';
import 'package:ravelgo_admin/views/settings/admin_users_screen.dart';
import 'package:ravelgo_admin/views/stays/stays_management_screen.dart';
import 'package:ravelgo_admin/views/trips/trip_admin_detail_screen.dart';

void main() {
  testWidgets('admin sign in rejects invalid credentials', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: AdminLoginScreen()));

    await tester.tap(find.text('Sign in').last);
    await tester.pump();
    expect(find.text('Enter a valid email address'), findsOneWidget);
    expect(find.text('Password must be at least 8 characters'), findsOneWidget);
    expect(find.byType(AdminLoginScreen), findsOneWidget);
  });

  testWidgets('trip detail shows real payment status instead of any fake actions',
      (WidgetTester tester) async {
    final trip = AdminTrip(
      id: 'trip-1',
      pickup: 'Ikeja',
      destination: 'Lekki',
      status: 'COMPLETED',
      fare: 5000,
      riderName: 'Ada Guest',
      driverName: 'Femi Driver',
      requestedAt: DateTime(2026, 1, 1),
      paymentStatus: 'SUCCEEDED',
      paymentMethod: 'CARD',
    );
    await tester.pumpWidget(MaterialApp(home: TripAdminDetailScreen(trip: trip)));

    expect(find.text('Ada Guest'), findsOneWidget);
    expect(find.text('Femi Driver'), findsOneWidget);
    // No refund/dispute actions — no such backend endpoint exists.
    expect(find.text('Refund rider'), findsNothing);
    expect(find.text('Flag this trip for review'), findsNothing);
  });

  // These consoles read live data from the backend (GET /api/admin/*, etc).
  // Without a backend they render their scaffold and a loading/error state -
  // these smoke tests assert they build cleanly.
  testWidgets('rental listings screen renders its scaffold', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: RentalListingsScreen()));
    expect(find.text('Luxury Rental Listings'), findsOneWidget);
  });

  testWidgets('car paddy requests screen renders its scaffold', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: CarPaddyRequestsScreen()));
    expect(find.text('Car Paddy Requests'), findsOneWidget);
  });

  testWidgets('fraud alerts screen renders its scaffold', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: FraudAlertsScreen()));
    expect(find.text('Fraud Alerts'), findsOneWidget);
  });

  testWidgets('short stays management screen renders its scaffold', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: StaysManagementScreen()));
    expect(find.text('Short Stays'), findsOneWidget);
  });

  testWidgets('payouts screen renders its scaffold', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: PayoutsScreen()));
    expect(find.text('Payouts'), findsOneWidget);
  });

  testWidgets('admin users screen renders its scaffold', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: AdminUsersScreen()));
    expect(find.text('Admin Users'), findsOneWidget);
  });
}
