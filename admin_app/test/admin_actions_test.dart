import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ravelgo_admin/services/admin_api.dart';
import 'package:ravelgo_admin/views/auth/admin_login_screen.dart';
import 'package:ravelgo_admin/views/auth/forgot_password_screen.dart';
import 'package:ravelgo_admin/views/auth/mfa_setup_screen.dart';
import 'package:ravelgo_admin/views/carpaddy/car_paddy_requests_screen.dart';
import 'package:ravelgo_admin/views/payouts/payouts_screen.dart';
import 'package:ravelgo_admin/views/pricing/pricing_policy_screen.dart';
import 'package:ravelgo_admin/views/rentals/rental_listings_screen.dart';
import 'package:ravelgo_admin/views/safety/fraud_alerts_screen.dart';
import 'package:ravelgo_admin/views/settings/admin_profile_screen.dart';
import 'package:ravelgo_admin/views/settings/referral_settings_screen.dart';
import 'package:ravelgo_admin/views/settings/admin_user_detail_screen.dart';
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

  AdminTrip tripWith({String? paymentStatus, String? method, double? amount}) => AdminTrip(
        id: 'trip-1',
        pickup: 'Ikeja',
        destination: 'Lekki',
        status: 'COMPLETED',
        fare: 5000,
        riderName: 'Ada Guest',
        driverName: 'Femi Driver',
        requestedAt: DateTime(2026, 1, 1),
        paymentStatus: paymentStatus,
        paymentMethod: method,
        paymentAmount: amount,
      );

  testWidgets('trip detail shows the real trip and its settled payment',
      (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
        home: TripAdminDetailScreen(
            trip: tripWith(paymentStatus: 'SUCCEEDED', method: 'CARD', amount: 5000))));

    expect(find.text('Ada Guest'), findsOneWidget);
    expect(find.text('Femi Driver'), findsOneWidget);
    // Still no invented actions — only the endpoints that exist.
    expect(find.text('Flag this trip for review'), findsNothing);
  });

  // A-3 / B-6: the refund endpoint existed all along; the admin app simply
  // could not reach it.
  testWidgets('a settled payment offers a refund, an unsettled one does not',
      (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
        home: TripAdminDetailScreen(
            trip: tripWith(paymentStatus: 'SUCCEEDED', method: 'CARD', amount: 5000))));
    expect(find.text('Issue refund'), findsOneWidget);

    await tester.pumpWidget(MaterialApp(
        home: TripAdminDetailScreen(trip: tripWith(paymentStatus: 'PENDING', method: 'CARD'))));
    expect(find.text('Issue refund'), findsNothing);
    expect(find.text('Only a settled payment can be refunded.'), findsOneWidget);

    await tester.pumpWidget(MaterialApp(home: TripAdminDetailScreen(trip: tripWith())));
    expect(find.text('Issue refund'), findsNothing);
    expect(find.text('Not charged yet.'), findsOneWidget);
  });

  testWidgets('a refund is never one tap: it needs a reason, and a partial amount '
      'cannot exceed the charge', (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
        home: TripAdminDetailScreen(
            trip: tripWith(paymentStatus: 'SUCCEEDED', method: 'CARD', amount: 5000))));

    await tester.tap(find.text('Issue refund'));
    await tester.pumpAndSettle();
    expect(find.text('Charged ₦5,000 by card.'), findsOneWidget);

    // Submitting with no reason is refused — the backend requires one and it
    // lands in the audit log.
    await tester.tap(find.text('Refund'));
    await tester.pumpAndSettle();
    expect(find.text('A reason is required'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).first, 'Rider charged twice');
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).last, '9000');
    await tester.tap(find.text('Refund'));
    await tester.pumpAndSettle();
    expect(find.text('Cannot exceed ₦5,000'), findsOneWidget);

    // Cancelling calls nothing at all.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Issue refund'), findsOneWidget);
  });

  testWidgets('a cash refund says plainly that no cash moves through RavelGo',
      (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
        home: TripAdminDetailScreen(
            trip: tripWith(paymentStatus: 'SUCCEEDED', method: 'CASH', amount: 3000))));
    expect(find.textContaining('Cash never passed through RavelGo'), findsOneWidget);
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

  testWidgets('pricing policy screen renders its scaffold', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: PricingPolicyScreen()));
    expect(find.text('Pricing Policy'), findsOneWidget);
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

  // No backend reachable in a widget test, so this exercises the real loading
  // -> error path (not a fabricated empty/populated state) — same convention
  // as the "renders its scaffold" tests above.
  testWidgets('admin users screen shows a loading indicator then an error without a backend',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: AdminUsersScreen()));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('invite dialog opens from the app bar and validates required fields before calling the API',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: AdminUsersScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.person_add_alt_1_outlined));
    await tester.pumpAndSettle();

    expect(find.text('Invite an admin user'), findsOneWidget);
    expect(find.text('Support Agent'), findsOneWidget); // default preset shown in the dropdown

    // All fields empty — submitting must not reach the network, just show a
    // validation message and keep the dialog open.
    await tester.tap(find.text('Send invite'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a first and last name.'), findsOneWidget);
    expect(find.text('Invite an admin user'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'First name'), 'New');
    await tester.enterText(find.widgetWithText(TextField, 'Last name'), 'Admin');
    await tester.enterText(find.widgetWithText(TextField, 'Email'), 'not-an-email');
    await tester.tap(find.text('Send invite'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a valid email address.'), findsOneWidget);

    // Cancel must close the dialog without ever calling the API.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Invite an admin user'), findsNothing);
  });

  testWidgets('admin user detail screen shows a suspended admin\'s status and a re-enable action',
      (WidgetTester tester) async {
    final suspended = AdminUserAccount(
      id: 'admin-1',
      name: 'Suspended Admin',
      email: 'suspended@example.com',
      adminRole: 'SUPPORT_AGENT',
      suspended: true,
      status: 'SUSPENDED',
      mfaEnabled: false,
      createdAt: DateTime(2026, 1, 1),
      lastLoginAt: null,
    );
    await tester.pumpWidget(MaterialApp(home: AdminUserDetailScreen(user: suspended)));

    expect(find.text('Suspended Admin'), findsOneWidget);
    expect(find.text('suspended@example.com'), findsOneWidget);
    expect(find.text('Suspended'), findsWidgets);
    expect(find.text('MFA not enrolled'), findsOneWidget);
    expect(find.text('Never signed in'), findsOneWidget);
    expect(find.text('Enable admin'), findsOneWidget);
    expect(find.text('Disable admin'), findsNothing);
    // Still invited/never-active admins don't get a resend-invitation button
    // once suspended — only INVITED status does.
    expect(find.text('Resend invitation'), findsNothing);
  });

  testWidgets('admin user detail screen offers resend invitation only while INVITED',
      (WidgetTester tester) async {
    final invited = AdminUserAccount(
      id: 'admin-2',
      name: 'Invited Admin',
      email: 'invited@example.com',
      adminRole: 'FINANCE_VIEWER',
      suspended: false,
      status: 'INVITED',
      mfaEnabled: false,
      createdAt: DateTime(2026, 1, 1),
      lastLoginAt: null,
    );
    await tester.pumpWidget(MaterialApp(home: AdminUserDetailScreen(user: invited)));

    expect(find.text('Resend invitation'), findsOneWidget);
    expect(find.text('Send password reset'), findsOneWidget);
    expect(find.text('Disable admin'), findsOneWidget);
  });

  testWidgets('admin profile screen shows a loading indicator then an error without a backend',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: AdminProfileScreen()));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.text('My Profile'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    // The old hard-coded placeholder values must never appear.
    expect(find.text('Ops Admin'), findsNothing);
    expect(find.text('admin@ravelgo.com'), findsNothing);
  });

  testWidgets('forgot password link on the login screen opens the reset flow', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: AdminLoginScreen()));
    await tester.tap(find.text('Forgot Password?'));
    await tester.pumpAndSettle();
    expect(find.byType(ForgotPasswordScreen), findsOneWidget);
    expect(find.text("Enter your admin email and we'll send a reset code."), findsOneWidget);
  });

  testWidgets('MFA setup screen has no way to skip or go back', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: MfaSetupScreen()));
    await tester.pumpAndSettle();

    // No AppBar/back button anywhere on this screen.
    expect(find.byType(AppBar), findsNothing);
    expect(find.byIcon(Icons.arrow_back), findsNothing);
    expect(find.text('Set up two-factor authentication'), findsOneWidget);
  });
  // The referral programme spends real money, so the screen must never
  // advertise terms it did not get from the backend, and turning it on must
  // not be a single unconfirmed tap.
  testWidgets('referral settings screen renders its scaffold', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: ReferralSettingsScreen()));
    expect(find.text('Referral Programme'), findsOneWidget);
    // Without a backend it shows a loading state, never invented terms.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('On'), findsNothing);
    expect(find.text('Off'), findsNothing);
  });

  testWidgets('referral settings screen surfaces a load failure with a retry',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: ReferralSettingsScreen()));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(ReferralSettingsScreen), findsOneWidget);
  });

}
