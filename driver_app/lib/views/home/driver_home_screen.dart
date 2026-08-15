import 'package:flutter/material.dart';
import 'package:ravelgo_driver_app/models/driver_profile.dart';
import 'package:ravelgo_driver_app/models/ride_request.dart';
import 'package:ravelgo_driver_app/services/api_client.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';
import 'package:ravelgo_driver_app/views/riderequest/incoming_request_sheet.dart';
import 'package:ravelgo_driver_app/views/trip/active_trip_screen.dart';

class DriverHomeScreen extends StatefulWidget {
  final DriverProfile profile;
  final ValueChanged<bool> onOnlineToggle;

  const DriverHomeScreen({super.key, required this.profile, required this.onOnlineToggle});

  @override
  State<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends State<DriverHomeScreen> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _driverData = {};

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

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final response = await ApiClient().get('/drivers/me');
      if (!mounted) return;
      setState(() {
        _driverData = Map<String, dynamic>.from(response);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

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

  String _statTotalTrips() {
    final total = _driverData['totalTrips'];
    return total != null ? '$total' : '--';
  }

  String _statRating() {
    final rating = _driverData['rating'];
    return rating != null ? (rating as num).toStringAsFixed(1) : '--';
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.profile;

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
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('Failed to load profile', style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600)),
                              const SizedBox(height: 8),
                              Text(_error!, style: const TextStyle(fontSize: 12, color: Colors.black54), textAlign: TextAlign.center),
                              const SizedBox(height: 16),
                              AppComponents.outlineButton(text: "Retry", onPressed: () { setState(() { _loading = true; _error = null; }); _loadData(); }),
                            ],
                          ),
                        ),
                      )
                    : SingleChildScrollView(
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
                                  Switch(value: profile.isOnline, activeColor: AppColors.primaryDark, onChanged: widget.onOnlineToggle),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(child: AppComponents.statChip("Rating", _statRating())),
                                const SizedBox(width: 12),
                                Expanded(child: AppComponents.statChip("Total trips", _statTotalTrips())),
                                const SizedBox(width: 12),
                                Expanded(child: AppComponents.statChip("Status", _driverData['status'] ?? '--')),
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
                                decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.04), borderRadius: BorderRadius.circular(12)),
                                child: const Text(
                                  "Go online to start receiving ride, courier and delivery requests matched to your preferences.",
                                  style: TextStyle(fontSize: 13, color: Colors.black54),
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
