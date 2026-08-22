import 'package:flutter/material.dart';
import 'package:ravelgo_driver_app/services/driver_session.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';
import 'package:ravelgo_driver_app/views/account/profile_screen.dart';
import 'package:ravelgo_driver_app/views/assistance/driver_assistance_screen.dart';
import 'package:ravelgo_driver_app/views/auth/login_screen.dart';
import 'package:ravelgo_driver_app/views/carpaddy/car_paddy_screen.dart';
import 'package:ravelgo_driver_app/views/documents/my_documents_screen.dart';
import 'package:ravelgo_driver_app/views/incentives/incentives_screen.dart';
import 'package:ravelgo_driver_app/views/preferences/driver_preferences_screen.dart';
import 'package:ravelgo_driver_app/views/ratings/my_ratings_screen.dart';
import 'package:ravelgo_driver_app/views/rentals/list_vehicle_for_rental_screen.dart';
import 'package:ravelgo_driver_app/views/safety/emergency_screen.dart';
import 'package:ravelgo_driver_app/views/subscription/driver_subscription_screen.dart';
import 'package:ravelgo_driver_app/views/support/contact_us_screen.dart';
import 'package:ravelgo_driver_app/views/support/faq_screen.dart';
import 'package:ravelgo_driver_app/views/vehicles/vehicle_list_screen.dart';

class AccountScreen extends StatelessWidget {
  final bool embedded;
  const AccountScreen({super.key, this.embedded = false});

  @override
  Widget build(BuildContext context) {
    final body = SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (embedded) AppComponents.sectionTitle("Account"),
          InkWell(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen())),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: AppComponents.cardDecoration(),
              child: Row(
                children: [
                  const CircleAvatar(radius: 26, backgroundColor: Color(0xFFF0F0F0), child: Icon(Icons.person, color: Colors.black45)),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Thelma Ibeh", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                        SizedBox(height: 4),
                        Text("View & edit profile", style: TextStyle(fontSize: 12, color: Colors.black54)),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            decoration: AppComponents.cardDecoration(),
            child: Column(
              children: [
                AppComponents.tile(title: "My Documents", leading: Icons.description_outlined, onTap: () => _go(context, const MyDocumentsScreen())),
                AppComponents.divider(),
                AppComponents.tile(title: "My Vehicles", leading: Icons.directions_car_outlined, onTap: () => _go(context, const VehicleListScreen())),
                AppComponents.divider(),
                AppComponents.tile(title: "Car Paddy – License Renewal", leading: Icons.badge_outlined, onTap: () => _go(context, const CarPaddyScreen())),
                AppComponents.divider(),
                AppComponents.tile(title: "List Car for Luxury Rental", leading: Icons.key_outlined, onTap: () => _go(context, const ListVehicleForRentalScreen())),
                AppComponents.divider(),
                AppComponents.tile(title: "Subscription Plan", leading: Icons.workspace_premium_outlined, onTap: () => _go(context, const DriverSubscriptionScreen())),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            decoration: AppComponents.cardDecoration(),
            child: Column(
              children: [
                AppComponents.tile(title: "Driver Assistance Mode", leading: Icons.alt_route_outlined, onTap: () => _go(context, const DriverAssistanceScreen())),
                AppComponents.divider(),
                AppComponents.tile(title: "Incentives & Badges", leading: Icons.emoji_events_outlined, onTap: () => _go(context, const IncentivesScreen())),
                AppComponents.divider(),
                AppComponents.tile(title: "Ride Preferences", leading: Icons.tune_outlined, onTap: () => _go(context, const DriverPreferencesScreen())),
                AppComponents.divider(),
                AppComponents.tile(title: "My Ratings", leading: Icons.star_outline, onTap: () => _go(context, const MyRatingsScreen())),
                AppComponents.divider(),
                AppComponents.tile(title: "Safety & Emergency", leading: Icons.shield_outlined, onTap: () => _go(context, const EmergencyScreen())),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            decoration: AppComponents.cardDecoration(),
            child: Column(
              children: [
                AppComponents.tile(title: "FAQ", leading: Icons.help_outline, onTap: () => _go(context, const FAQScreen())),
                AppComponents.divider(),
                AppComponents.tile(title: "Contact Support", leading: Icons.phone_outlined, onTap: () => _go(context, const ContactUsScreen())),
                AppComponents.divider(),
                AppComponents.tile(
                  title: "Log out",
                  leading: Icons.logout,
                  // Clears the session (DriverSession.signOut) before
                  // navigating — a prior version of this screen skipped
                  // that call and just changed routes.
                  onTap: () async {
                    await DriverSession.instance.signOut();
                    if (!context.mounted) return;
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(builder: (_) => const LoginScreen()),
                      (route) => false,
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );

    if (embedded) return body;
    return Scaffold(appBar: AppBar(title: const Text("Account")), body: body);
  }

  void _go(BuildContext context, Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }
}
