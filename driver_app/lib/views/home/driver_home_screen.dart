import 'package:flutter/material.dart';
import 'package:ravelgo_driver_app/models/driver_profile.dart';
import 'package:ravelgo_driver_app/models/ride_request.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';
import 'package:ravelgo_driver_app/views/notifications/notifications_screen.dart';
import 'package:ravelgo_driver_app/views/riderequest/incoming_request_sheet.dart';
import 'package:ravelgo_driver_app/views/trip/active_trip_screen.dart';

class DriverHomeScreen extends StatelessWidget {
  final DriverProfile profile;
  final ValueChanged<bool> onOnlineToggle;

  const DriverHomeScreen({super.key, required this.profile, required this.onOnlineToggle});

  static const _demoRequest = RideRequest(
    riderName: "Amaka O.",
    riderRating: 4.9,
    pickup: "14 Admiralty Way, Lekki Phase 1",
    destination: "Landmark Beach, Victoria Island",
    estimatedFare: 3200,
    distanceKm: 8.4,
    etaMinutes: 6,
    preferredLanguage: "English",
    quietModeRequested: true,
    pickupNote: "Please call when you arrive, gate is locked.",
  );

  Future<void> _simulateRequest(BuildContext context) async {
    final accepted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const IncomingRequestSheet(request: _demoRequest),
    );
    if (accepted == true && context.mounted) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const ActiveTripScreen(request: _demoRequest)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          Stack(
            children: [
              Image.asset('assets/fake_map.png', width: double.infinity, height: 320, fit: BoxFit.cover),
              Positioned(
                top: 16,
                left: 16,
                right: 16,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Builder(
                      builder: (context) => GestureDetector(
                        onTap: () => Scaffold.of(context).openDrawer(),
                        child: const CircleAvatar(backgroundColor: AppColors.surface, child: Icon(Icons.menu, color: AppColors.textPrimary)),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.push(context,
                          MaterialPageRoute(builder: (_) => const NotificationsScreen())),
                      child: const CircleAvatar(
                          backgroundColor: AppColors.surface,
                          child: Icon(Icons.notifications_none, color: AppColors.textPrimary)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: AppComponents.cardDecoration(),
                    child: Row(
                      children: [
                        Icon(Icons.circle, size: 12, color: profile.isOnline ? AppColors.online : AppColors.offline),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            profile.isOnline ? "You're online and visible to riders" : "You're offline",
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        Switch(value: profile.isOnline, onChanged: onOnlineToggle),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(child: AppComponents.statChip("Today's earnings", "₦18,400")),
                      const SizedBox(width: 12),
                      Expanded(child: AppComponents.statChip("Trips today", "6")),
                      const SizedBox(width: 12),
                      Expanded(child: AppComponents.statChip("Online hours", "5h 20m")),
                    ],
                  ),
                  const SizedBox(height: 20),
                  if (profile.isOnline)
                    AppComponents.primaryButton(
                      text: "Simulate incoming ride request",
                      onPressed: () => _simulateRequest(context),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(color: AppColors.textPrimary.withValues(alpha: 0.04), borderRadius: BorderRadius.circular(12)),
                      child: const Text(
                        "Go online to start receiving ride, courier and delivery requests matched to your preferences.",
                        style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
