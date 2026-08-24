import 'package:flutter/material.dart';
import 'package:ravelgo_driver_app/models/driver_profile.dart';
import 'package:ravelgo_driver_app/models/ride_request.dart';
import 'package:ravelgo_driver_app/services/driver_api.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';
import 'package:ravelgo_driver_app/views/riderequest/incoming_request_sheet.dart';
import 'package:ravelgo_driver_app/views/trip/active_trip_screen.dart';

enum _SummaryLoadState { loading, loaded, error }

class DriverHomeScreen extends StatefulWidget {
  final DriverProfile profile;
  final ValueChanged<bool> onOnlineToggle;
  final DriverApi api;

  const DriverHomeScreen({
    super.key,
    required this.profile,
    required this.onOnlineToggle,
    required this.api,
  });

  @override
  State<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends State<DriverHomeScreen> {
  _SummaryLoadState _state = _SummaryLoadState.loading;
  DriverSummary? _summary;
  String _errorMessage = "Unable to load dashboard";

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
    _loadSummary();
  }

  Future<void> _loadSummary() async {
    setState(() => _state = _SummaryLoadState.loading);
    try {
      final summary = await widget.api.fetchSummary();
      if (!mounted) return;
      setState(() {
        _summary = summary;
        _state = _SummaryLoadState.loaded;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e is DriverApiException ? e.message : "Unable to load dashboard";
        _state = _SummaryLoadState.error;
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

  String _formatNaira(double amount) => "₦${amount.toStringAsFixed(0)}";

  String _formatHours(double hours) {
    final wholeHours = hours.floor();
    final minutes = ((hours - wholeHours) * 60).round();
    return "${wholeHours}h ${minutes}m";
  }

  Widget _buildStats() {
    switch (_state) {
      case _SummaryLoadState.loading:
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 24),
          alignment: Alignment.center,
          child: const Column(
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 12),
              Text("Loading your dashboard...", style: TextStyle(color: Colors.black54)),
            ],
          ),
        );
      case _SummaryLoadState.error:
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: AppComponents.cardDecoration(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Unable to load dashboard", style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(_errorMessage, style: const TextStyle(fontSize: 12.5, color: Colors.black54)),
              const SizedBox(height: 12),
              AppComponents.outlineButton(text: "Try again", onPressed: _loadSummary),
            ],
          ),
        );
      case _SummaryLoadState.loaded:
        final summary = _summary!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: AppComponents.statChip("Today's earnings", _formatNaira(summary.netEarningsToday))),
                const SizedBox(width: 12),
                Expanded(child: AppComponents.statChip("Trips today", "${summary.tripsToday}")),
                const SizedBox(width: 12),
                Expanded(child: AppComponents.statChip("Online hours", _formatHours(summary.onlineHoursToday))),
              ],
            ),
            if (!summary.hasActivityToday) ...[
              const SizedBox(height: 8),
              const Text("No activity yet", style: TextStyle(fontSize: 12.5, color: Colors.black45)),
            ],
          ],
        );
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
            child: RefreshIndicator(
              onRefresh: _loadSummary,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: AppComponents.cardDecoration(),
                      child: Row(
                        children: [
                          Icon(Icons.circle, size: 12, color: widget.profile.isOnline ? AppColors.online : AppColors.offline),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              widget.profile.isOnline ? "You're online and visible to riders" : "You're offline",
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                          Switch(
                            value: widget.profile.isOnline,
                            activeColor: AppColors.primaryDark,
                            onChanged: widget.onOnlineToggle,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildStats(),
                    const SizedBox(height: 20),
                    if (widget.profile.isOnline)
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
          ),
        ],
      ),
    );
  }
}
