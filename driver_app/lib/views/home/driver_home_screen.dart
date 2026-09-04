import 'dart:async';
import 'package:flutter/material.dart';
import 'package:ravelgo_driver_app/config/currency.dart';
import 'package:ravelgo_driver_app/models/driver_profile.dart';
import 'package:ravelgo_driver_app/services/api_client.dart';
import 'package:ravelgo_driver_app/services/driver_api.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';
import 'package:ravelgo_driver_app/views/notifications/notifications_screen.dart';
import 'package:ravelgo_driver_app/views/riderequest/incoming_request_sheet.dart';
import 'package:ravelgo_driver_app/views/trip/active_trip_screen.dart';

/// The driver's home. When online it polls the backend for a trip the matching
/// engine has assigned to this driver (status MATCHED) and surfaces it as a
/// real incoming request — there is no simulated ride and no demo data (P0 #3).
/// Accepting opens the live trip screen; declining cancels the trip on the
/// backend. Today's earnings/trips are derived from the driver's real completed
/// trips.
class DriverHomeScreen extends StatefulWidget {
  final DriverProfile profile;
  final ValueChanged<bool> onOnlineToggle;

  const DriverHomeScreen({super.key, required this.profile, required this.onOnlineToggle});

  @override
  State<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends State<DriverHomeScreen> {
  Timer? _poll;
  bool _handlingRequest = false; // a request sheet / active trip is on screen
  bool _loadingTrips = false;

  int _tripsToday = 0;
  double _earningsToday = 0;

  @override
  void initState() {
    super.initState();
    _refreshTrips();
    if (widget.profile.isOnline) _startPolling();
  }

  @override
  void didUpdateWidget(DriverHomeScreen old) {
    super.didUpdateWidget(old);
    if (widget.profile.isOnline && _poll == null) {
      _startPolling();
    } else if (!widget.profile.isOnline && _poll != null) {
      _stopPolling();
    }
  }

  @override
  void dispose() {
    _stopPolling();
    super.dispose();
  }

  void _startPolling() {
    _poll?.cancel();
    // Poll for a matched trip while online. The driver is auto-assigned by the
    // backend matcher, so this is a genuine check for real work, not a fake.
    _poll = Timer.periodic(const Duration(seconds: 8), (_) => _checkForMatch());
    _checkForMatch();
  }

  void _stopPolling() {
    _poll?.cancel();
    _poll = null;
  }

  bool _isToday(DateTime d) {
    final now = DateTime.now();
    return d.year == now.year && d.month == now.month && d.day == now.day;
  }

  Future<List<DriverTrip>> _loadTrips() async {
    return DriverApi.myTrips();
  }

  Future<void> _refreshTrips() async {
    if (_loadingTrips) return;
    setState(() => _loadingTrips = true);
    try {
      final trips = await _loadTrips();
      if (!mounted) return;
      final completedToday =
          trips.where((t) => t.status == 'COMPLETED' && _isToday(t.requestedAt)).toList();
      setState(() {
        _tripsToday = completedToday.length;
        _earningsToday = completedToday.fold<double>(0, (sum, t) => sum + t.fare);
      });
    } catch (_) {
      // Non-fatal — the home screen still renders with the last known values.
    } finally {
      if (mounted) setState(() => _loadingTrips = false);
    }
  }

  Future<void> _checkForMatch() async {
    if (_handlingRequest || !mounted) return;
    List<DriverTrip> trips;
    try {
      trips = await _loadTrips();
    } catch (_) {
      return;
    }
    if (!mounted) return;

    // Refresh today's stats off the same fetch.
    final completedToday =
        trips.where((t) => t.status == 'COMPLETED' && _isToday(t.requestedAt)).toList();
    setState(() {
      _tripsToday = completedToday.length;
      _earningsToday = completedToday.fold<double>(0, (sum, t) => sum + t.fare);
    });

    DriverTrip? match;
    for (final t in trips) {
      if (t.status == 'MATCHED') {
        match = t;
        break;
      }
    }
    if (match != null) await _presentRequest(match);
  }

  Future<void> _presentRequest(DriverTrip trip) async {
    if (_handlingRequest) return;
    _handlingRequest = true;
    try {
      final accepted = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        isDismissible: false,
        enableDrag: false,
        builder: (_) => IncomingRequestSheet(trip: trip),
      );
      if (!mounted) return;
      if (accepted == true) {
        // The trip is already MATCHED (accepted); the live screen drives the
        // real MATCHED→IN_PROGRESS→COMPLETED transitions.
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => ActiveTripScreen(trip: trip)),
        );
        if (mounted) await _refreshTrips();
      } else if (accepted == false) {
        await _decline(trip);
      }
    } finally {
      _handlingRequest = false;
    }
  }

  Future<void> _decline(DriverTrip trip) async {
    try {
      await DriverApi.updateTripStatus(trip.id, 'CANCELLED');
    } catch (e) {
      if (!mounted) return;
      final msg = e is ApiException ? e.message : e.toString();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
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
                        child: const CircleAvatar(
                            backgroundColor: AppColors.surface,
                            child: Icon(Icons.menu, color: AppColors.textPrimary)),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.push(
                          context, MaterialPageRoute(builder: (_) => const NotificationsScreen())),
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
                  if (!profile.isApproved)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: AppComponents.cardDecoration(),
                      child: Row(
                        children: [
                          const Icon(Icons.hourglass_top, size: 20, color: AppColors.warning),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  "Application under review",
                                  style: TextStyle(fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  profile.status == 'SUSPENDED'
                                      ? "Your account is suspended. Contact support for help."
                                      : "We'll notify you as soon as your documents are approved and you can go online.",
                                  style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    )
                  else
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
                          Switch(value: profile.isOnline, onChanged: widget.onOnlineToggle),
                        ],
                      ),
                    ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(child: AppComponents.statChip("Today's earnings", Currency.format(_earningsToday, decimals: 0))),
                      const SizedBox(width: 12),
                      Expanded(child: AppComponents.statChip("Trips today", "$_tripsToday")),
                      const SizedBox(width: 12),
                      Expanded(child: AppComponents.statChip("Rating", profile.rating.toStringAsFixed(1))),
                    ],
                  ),
                  const SizedBox(height: 20),
                  if (!profile.isApproved)
                    const SizedBox.shrink()
                  else if (profile.isOnline)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: AppComponents.cardDecoration(),
                      child: Row(
                        children: [
                          const SizedBox(
                              height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(
                              _handlingRequest
                                  ? "You have a ride request."
                                  : "Waiting for ride requests. We'll notify you the moment one is matched to you.",
                              style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                          color: AppColors.textPrimary.withValues(alpha: 0.04), borderRadius: BorderRadius.circular(12)),
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
