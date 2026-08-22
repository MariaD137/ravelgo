import 'package:flutter/material.dart';
import 'package:ravelgo_driver_app/models/driver_operational_state.dart';
import 'package:ravelgo_driver_app/models/driver_profile.dart';
import 'package:ravelgo_driver_app/models/ride_request.dart';
import 'package:ravelgo_driver_app/services/driver_session.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';
import 'package:ravelgo_driver_app/views/courier/available_courier_requests_screen.dart';
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
                        child: const CircleAvatar(backgroundColor: Colors.white, child: Icon(Icons.menu, color: Colors.black)),
                      ),
                    ),
                    const CircleAvatar(backgroundColor: Colors.white, child: Icon(Icons.notifications_none, color: Colors.black)),
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
                        Switch(value: profile.isOnline, activeColor: AppColors.primaryDark, onChanged: onOnlineToggle),
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
                  // Gated by DriverSession.instance.state, not just
                  // profile.isOnline: this is a UI convenience (Part 15) so
                  // the driver isn't shown "start a new job" actions while
                  // already on one — the backend independently rejects the
                  // same conflicting action regardless of what this button
                  // shows (Part 18), so this gating never needs to be
                  // perfectly correct to keep the driver safe from a
                  // double-booking, only to keep the UI honest.
                  ListenableBuilder(
                    listenable: DriverSession.instance,
                    builder: (context, _) {
                      final busy = DriverSession.instance.state.isBusy;
                      if (!profile.isOnline) {
                        return Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.04),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text(
                            "Go online to start receiving ride, courier and delivery requests matched to your preferences.",
                            style: TextStyle(fontSize: 13, color: Colors.black54),
                          ),
                        );
                      }
                      if (busy) {
                        return Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            "You're ${DriverSession.instance.state.label.toLowerCase()} — new ride, delivery and rental requests are paused until it's done.",
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                          ),
                        );
                      }
                      return Column(
                        children: [
                          AppComponents.primaryButton(
                            text: "Simulate incoming ride request",
                            onPressed: () => _simulateRequest(context),
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const AvailableCourierRequestsScreen()),
                              );
                            },
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(double.infinity, 50),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: const Text("View available deliveries"),
                          ),
                        ],
                      );
                    },
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
