import 'package:flutter/material.dart';
import 'package:ravelgo_driver_app/models/driver_profile.dart';
import 'package:ravelgo_driver_app/services/auth_service.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';
import 'package:ravelgo_driver_app/views/assistance/driver_assistance_screen.dart';
import 'package:ravelgo_driver_app/views/auth/login_screen.dart';
import 'package:ravelgo_driver_app/views/carpaddy/car_paddy_screen.dart';
import 'package:ravelgo_driver_app/views/deliveries/deliveries_screen.dart';
import 'package:ravelgo_driver_app/views/documents/my_documents_screen.dart';
import 'package:ravelgo_driver_app/views/incentives/incentives_screen.dart';
import 'package:ravelgo_driver_app/views/preferences/driver_preferences_screen.dart';
import 'package:ravelgo_driver_app/views/ratings/my_ratings_screen.dart';
import 'package:ravelgo_driver_app/views/rentals/list_vehicle_for_rental_screen.dart';
import 'package:ravelgo_driver_app/views/rentals/my_rental_listings_screen.dart';
import 'package:ravelgo_driver_app/views/safety/emergency_screen.dart';
import 'package:ravelgo_driver_app/views/subscription/driver_subscription_screen.dart';
import 'package:ravelgo_driver_app/views/support/contact_us_screen.dart';
import 'package:ravelgo_driver_app/views/support/driver_support_screen.dart';
import 'package:ravelgo_driver_app/views/support/faq_screen.dart';
import 'package:ravelgo_driver_app/views/vehicles/vehicle_list_screen.dart';

class SideMenuDriver extends StatelessWidget {
  final DriverProfile profile;
  const SideMenuDriver({super.key, required this.profile});

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
                  const CircleAvatar(radius: 28, backgroundColor: AppColors.surfaceElevated, child: Icon(Icons.person, color: AppColors.textSecondary)),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("${profile.firstName} ${profile.lastName}", style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(Icons.star, color: AppColors.primary, size: 14),
                            const SizedBox(width: 4),
                            Text("${profile.rating}  ·  ${profile.totalTrips} trips", style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            _item(context, Icons.local_shipping_outlined, "Deliveries", () => const DeliveriesScreen()),
            _item(context, Icons.description_outlined, "My Documents", () => const MyDocumentsScreen()),
            _item(context, Icons.badge_outlined, "Car Paddy – License Renewal", () => const CarPaddyScreen()),
            _item(context, Icons.directions_car_outlined, "My Vehicles", () => const VehicleListScreen()),
            _item(context, Icons.key_outlined, "List Car for Luxury Rental", () => const ListVehicleForRentalScreen()),
            _item(context, Icons.event_note_outlined, "My Listings", () => const MyRentalListingsScreen()),
            _item(context, Icons.workspace_premium_outlined, "Subscription Plan", () => const DriverSubscriptionScreen()),
            _item(context, Icons.alt_route_outlined, "Driver Assistance Mode", () => const DriverAssistanceScreen()),
            _item(context, Icons.emoji_events_outlined, "Incentives & Badges", () => const IncentivesScreen()),
            _item(context, Icons.tune_outlined, "Ride Preferences", () => DriverPreferencesScreen(profile: profile)),
            _item(context, Icons.star_outline, "My Ratings", () => MyRatingsScreen(profile: profile)),
            _item(context, Icons.shield_outlined, "Safety & Emergency", () => const EmergencyScreen()),
            AppComponents.divider(),
            _item(context, Icons.help_outline, "FAQ", () => const FAQScreen()),
            _item(context, Icons.phone_outlined, "Contact Support", () => const ContactUsScreen()),
            _item(context, Icons.support_agent_outlined, "Support & Disputes", () => const DriverSupportScreen()),
            _item(context, Icons.logout, "Log out", () => const LoginScreen(), replace: true, preAction: AuthService.signOut),
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
            Icon(icon, size: 21, color: AppColors.textSecondary),
            const SizedBox(width: 16),
            Expanded(child: Text(label, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w500))),
          ],
        ),
      ),
    );
  }
}
