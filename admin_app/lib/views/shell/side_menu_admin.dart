import 'package:flutter/material.dart';
import 'package:ravelgo_admin/services/auth_service.dart';
import 'package:ravelgo_admin/theme/app_theme.dart';
import 'package:ravelgo_admin/views/audit/audit_log_screen.dart';
import 'package:ravelgo_admin/views/auth/admin_login_screen.dart';
import 'package:ravelgo_admin/views/carpaddy/car_paddy_requests_screen.dart';
import 'package:ravelgo_admin/views/couriers/courier_requests_screen.dart';
import 'package:ravelgo_admin/views/payments/payments_cash_screen.dart';
import 'package:ravelgo_admin/views/payouts/payouts_screen.dart';
import 'package:ravelgo_admin/views/pricing/pricing_surge_screen.dart';
import 'package:ravelgo_admin/views/promotions/loyalty_program_screen.dart';
import 'package:ravelgo_admin/views/rentals/rental_listings_screen.dart';
import 'package:ravelgo_admin/views/reports/analytics_screen.dart';
import 'package:ravelgo_admin/views/riders/rider_list_screen.dart';
import 'package:ravelgo_admin/views/safety/emergency_alerts_screen.dart';
import 'package:ravelgo_admin/views/safety/fraud_alerts_screen.dart';
import 'package:ravelgo_admin/views/settings/admin_profile_screen.dart';
import 'package:ravelgo_admin/views/settings/admin_users_screen.dart';
import 'package:ravelgo_admin/views/settings/payment_settings_screen.dart';
import 'package:ravelgo_admin/views/stays/stays_management_screen.dart';
import 'package:ravelgo_admin/views/subscriptions/driver_subscriptions_screen.dart';
import 'package:ravelgo_admin/views/vehicles/vehicle_inventory_screen.dart';

class SideMenuAdmin extends StatelessWidget {
  const SideMenuAdmin({super.key});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: AppColors.surface,
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              color: AppColors.background,
              child: Row(
                children: [
                  const CircleAvatar(radius: 26, backgroundColor: AppColors.surface, child: Icon(Icons.admin_panel_settings_outlined, color: AppColors.textPrimary)),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Ops Admin", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                        SizedBox(height: 2),
                        Text("admin@ravelgo.com", style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            _item(context, Icons.people_outline, "Riders", () => const RiderListScreen()),
            _item(context, Icons.local_shipping_outlined, "Courier Requests", () => const CourierRequestsScreen()),
            _item(context, Icons.badge_outlined, "Car Paddy Requests", () => const CarPaddyRequestsScreen()),
            _item(context, Icons.key_outlined, "Luxury Rental Listings", () => const RentalListingsScreen()),
            _item(context, Icons.villa_outlined, "Short Stays", () => const StaysManagementScreen()),
            _item(context, Icons.directions_car_outlined, "Vehicle Inventory", () => const VehicleInventoryScreen()),
            _item(context, Icons.tune_outlined, "Pricing & Surge", () => const PricingSurgeScreen()),
            _item(context, Icons.workspace_premium_outlined, "Driver Subscriptions", () => const DriverSubscriptionsScreen()),
            _item(context, Icons.payments_outlined, "Payments & Cash", () => const PaymentsCashScreen()),
            _item(context, Icons.account_balance_wallet_outlined, "Payouts", () => const PayoutsScreen()),
            AppComponents.divider(),
            _item(context, Icons.warning_amber_outlined, "Fraud Alerts", () => const FraudAlertsScreen()),
            _item(context, Icons.sos, "Emergency Alerts", () => const EmergencyAlertsScreen()),
            _item(context, Icons.emoji_events_outlined, "Loyalty & Promotions", () => const LoyaltyProgramScreen()),
            AppComponents.divider(),
            _item(context, Icons.bar_chart_outlined, "Reports & Analytics", () => const AnalyticsScreen()),
            _item(context, Icons.receipt_long_outlined, "Audit Log", () => const AuditLogScreen()),
            _item(context, Icons.manage_accounts_outlined, "Admin Users", () => const AdminUsersScreen()),
            _item(context, Icons.settings_outlined, "Payment Settings", () => const PaymentSettingsScreen()),
            _item(context, Icons.person_outline, "My Profile", () => const AdminProfileScreen()),
            _item(context, Icons.logout, "Log out", () => const AdminLoginScreen(), replace: true, preAction: AuthService.signOut),
          ],
        ),
      ),
    );
  }

  Widget _item(BuildContext context, IconData icon, String label, Widget Function() builder, {bool replace = false, Future<void> Function()? preAction}) {
    return InkWell(
      onTap: () async {
        if (preAction != null) await preAction();
        if (!context.mounted) return;
        Navigator.pop(context);
        if (replace) {
          Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => builder()), (route) => false);
        } else {
          Navigator.push(context, MaterialPageRoute(builder: (_) => builder()));
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 21, color: AppColors.textPrimary),
            const SizedBox(width: 16),
            Expanded(child: Text(label, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w500))),
          ],
        ),
      ),
    );
  }
}
