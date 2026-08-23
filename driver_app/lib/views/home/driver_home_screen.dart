import 'package:flutter/material.dart';
import 'package:ravelgo_driver_app/models/driver_operational_state.dart';
import 'package:ravelgo_driver_app/services/driver_session.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';
import 'package:ravelgo_driver_app/views/courier/available_courier_requests_screen.dart';
import 'package:ravelgo_driver_app/views/riderequest/incoming_request_sheet.dart';
import 'package:ravelgo_driver_app/views/trip/active_trip_screen.dart';
import 'package:ravelgo_driver_app/widgets/live_map_preview.dart';

/// Real matching, not a simulation: [DriverSession] polls (and best-effort
/// WebSocket-pushes) GET /api/drivers/me/assignment while online and free,
/// and the moment it sees a real ACTIVE ride assignment
/// (`pendingRideAssignment`), this screen shows the incoming-request sheet
/// automatically — there is no "Simulate incoming ride request" button
/// anymore. See DRIVER_APP_REAL_MATCHING_READINESS.md.
class DriverHomeScreen extends StatefulWidget {
  const DriverHomeScreen({super.key});

  @override
  State<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends State<DriverHomeScreen> {
  bool _sheetShowing = false;
  bool _togglingOnline = false;

  @override
  void initState() {
    super.initState();
    DriverSession.instance.addListener(_onSessionChanged);
    // A pending assignment can already exist the moment this screen first
    // builds (e.g. the app was backgrounded mid-poll) — check once up
    // front rather than only reacting to a change.
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowIncomingRequest());
  }

  @override
  void dispose() {
    DriverSession.instance.removeListener(_onSessionChanged);
    super.dispose();
  }

  void _onSessionChanged() {
    if (!mounted) return;
    setState(() {});
    _maybeShowIncomingRequest();
  }

  Future<void> _maybeShowIncomingRequest() async {
    if (_sheetShowing) return;
    final trip = DriverSession.instance.pendingRideAssignment;
    if (trip == null) return;
    _sheetShowing = true;
    final acceptedTrip = await showModalBottomSheet<Map<String, dynamic>?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: false,
      enableDrag: false,
      builder: (_) => IncomingRequestSheet(trip: trip),
    );
    _sheetShowing = false;
    if (acceptedTrip != null && mounted) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => ActiveTripScreen(trip: acceptedTrip)));
    }
  }

  Future<void> _toggleOnline(bool value) async {
    setState(() => _togglingOnline = true);
    final ok = value ? await DriverSession.instance.setOnline() : await DriverSession.instance.setOffline();
    if (!mounted) return;
    setState(() => _togglingOnline = false);
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(DriverSession.instance.authErrorMessage ?? 'Could not update your status.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = DriverSession.instance.profile;
    // Driven by DriverSession.instance.state — set immediately by
    // setOnline()/setOffline()/markBusy()/reconcile() — rather than
    // profile.isOnline directly, so the UI updates the instant a toggle
    // succeeds instead of waiting on a profile reload.
    final isOnline = DriverSession.instance.state != DriverOperationalState.offline;
    final busy = DriverSession.instance.state.isBusy;

    return SafeArea(
      child: Column(
        children: [
          Stack(
            children: [
              const LiveMapPreview(height: 320),
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
                        Icon(Icons.circle, size: 12, color: isOnline ? AppColors.online : AppColors.offline),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            isOnline ? "You're online and visible to riders" : "You're offline",
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        _togglingOnline
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                            : Switch(value: isOnline, activeThumbColor: AppColors.primaryDark, onChanged: busy ? null : _toggleOnline),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (profile != null)
                    Row(
                      children: [
                        Expanded(child: AppComponents.statChip("Rating", profile.rating.toStringAsFixed(2))),
                        const SizedBox(width: 12),
                        Expanded(child: AppComponents.statChip("Total trips", '${profile.totalTrips}')),
                      ],
                    ),
                  const SizedBox(height: 20),
                  // Gated by DriverSession.instance.state, not just the
                  // online toggle: this is a UI convenience (Part 15) so
                  // the driver isn't shown "start a new job" actions while
                  // already on one — the backend independently rejects the
                  // same conflicting action regardless of what this button
                  // shows (Part 18), so this gating never needs to be
                  // perfectly correct to keep the driver safe from a
                  // double-booking, only to keep the UI honest.
                  Builder(
                    builder: (context) {
                      if (!isOnline) {
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
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: AppColors.online.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.wifi_tethering, size: 18, color: AppColors.online),
                                SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    "Listening for ride requests...",
                                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                                  ),
                                ),
                              ],
                            ),
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
