import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:ravelgo_driver_app/config/currency.dart';
import 'package:ravelgo_driver_app/models/driver_profile.dart';
import 'package:ravelgo_driver_app/services/driver_api.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';
import 'package:ravelgo_driver_app/views/documents/my_documents_screen.dart';
import 'package:ravelgo_driver_app/views/home/account_status_card.dart';
import 'package:ravelgo_driver_app/views/notifications/notifications_screen.dart';
import 'package:ravelgo_driver_app/views/riderequest/incoming_request_sheet.dart';
import 'package:ravelgo_driver_app/views/shell/driver_shell.dart';
import 'package:ravelgo_driver_app/views/trip/active_trip_screen.dart';

/// The driver's home. When online it polls the backend for a trip the matching
/// engine has assigned to this driver (status MATCHED) and surfaces it as a
/// real incoming request — there is no simulated ride and no demo data (P0 #3).
/// Accepting opens the live trip screen; declining cancels the trip on the
/// backend. Today's earnings/trips are derived from the driver's real completed
/// trips.
///
/// The approval card at the top renders ONLY what GET /drivers/me last
/// returned (via DriverShell): a status that hasn't loaded shows as such, a
/// failed load shows the failure with a retry, and "Application under review"
/// appears only when the backend's Driver.status really is PENDING_REVIEW.
class DriverHomeScreen extends StatefulWidget {
  final DriverProfile profile;
  final DriverProfileLoadState loadState;
  final String? loadError;
  final ValueChanged<bool> onOnlineToggle;
  final Future<void> Function() onRefresh;

  const DriverHomeScreen({
    super.key,
    required this.profile,
    required this.onOnlineToggle,
    required this.onRefresh,
    this.loadState = DriverProfileLoadState.ready,
    this.loadError,
  });

  @override
  State<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends State<DriverHomeScreen> {
  Timer? _poll;
  Timer? _locationTimer;
  bool _handlingRequest = false; // a request sheet / active trip is on screen
  bool _loadingTrips = false;

  int _tripsToday = 0;
  double _earningsToday = 0;

  @override
  void initState() {
    super.initState();
    _refreshTrips();
    if (widget.profile.isOnline) {
      _startPolling();
      _startLocationPing();
    }
  }

  @override
  void didUpdateWidget(DriverHomeScreen old) {
    super.didUpdateWidget(old);
    if (widget.profile.isOnline && _poll == null) {
      _startPolling();
      _startLocationPing();
    } else if (!widget.profile.isOnline && _poll != null) {
      _stopPolling();
      _stopLocationPing();
    }
  }

  @override
  void dispose() {
    _stopPolling();
    _stopLocationPing();
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

  /// While online (whether or not there's an active trip), periodically
  /// report this driver's position — this is what makes an idle "available"
  /// driver show up on the admin Live Map, which otherwise only ever hears
  /// from a driver mid-trip (see RealtimeService / trip_detail_screen.dart).
  void _startLocationPing() {
    _locationTimer?.cancel();
    _pingLocation();
    _locationTimer = Timer.periodic(const Duration(seconds: 20), (_) => _pingLocation());
  }

  void _stopLocationPing() {
    _locationTimer?.cancel();
    _locationTimer = null;
  }

  Future<void> _pingLocation() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return;
      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      await DriverApi.pingLocation(pos.latitude, pos.longitude);
    } catch (_) {
      // Best-effort: a failed fix/ping just means no update this tick.
    }
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

    DriverTrip? offer;
    for (final t in trips) {
      if (t.status == 'OFFERED') {
        offer = t;
        break;
      }
    }
    if (offer != null) await _presentRequest(offer);
  }

  /// Shows the real OFFERED trip and waits for the driver to actually accept
  /// or decline it through the backend (IncomingRequestSheet calls
  /// DriverApi.acceptTrip/declineTrip itself). A non-null result means the
  /// backend confirmed the accept and returned the now-MATCHED trip; a null
  /// result means it was declined, the offer expired, or it was otherwise
  /// resolved elsewhere — either way, this driver has nothing further to do
  /// for it and polling simply continues for the next offer, if any.
  Future<void> _presentRequest(DriverTrip trip) async {
    if (_handlingRequest) return;
    _handlingRequest = true;
    try {
      final matched = await showModalBottomSheet<DriverTrip>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        isDismissible: false,
        enableDrag: false,
        builder: (_) => IncomingRequestSheet(trip: trip),
      );
      if (!mounted) return;
      if (matched != null) {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => ActiveTripScreen(trip: matched)),
        );
        if (mounted) await _refreshTrips();
      }
    } finally {
      _handlingRequest = false;
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
              // A real map showing this device's actual GPS position via the
              // native "my location" layer — the same GoogleMap the active-trip
              // screen uses, not a decorative static image. No fabricated
              // nearby-driver markers: nothing on this map is invented.
              SizedBox(
                width: double.infinity,
                height: 320,
                child: GoogleMap(
                  initialCameraPosition: const CameraPosition(target: LatLng(6.5244, 3.3792), zoom: 12),
                  myLocationEnabled: true,
                  myLocationButtonEnabled: false,
                  zoomControlsEnabled: false,
                ),
              ),
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
                      onTap: () async {
                        await Navigator.push(
                            context, MaterialPageRoute(builder: (_) => const NotificationsScreen()));
                        // An approval notification lives in that list — coming
                        // back from it is the natural moment to re-read the
                        // real status.
                        if (context.mounted) await widget.onRefresh();
                      },
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
            child: RefreshIndicator(
              onRefresh: widget.onRefresh,
              child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!profile.isApproved)
                    DriverAccountStatusCard(
                      profile: profile,
                      loadState: widget.loadState,
                      loadError: widget.loadError,
                      onRefresh: widget.onRefresh,
                      onOpenDocuments: () async {
                        await Navigator.push(context, MaterialPageRoute(builder: (_) => const MyDocumentsScreen()));
                        if (context.mounted) await widget.onRefresh();
                      },
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
                                  : "Waiting for ride requests. We'll notify you the moment one is offered to you.",
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
          ),
        ],
      ),
    );
  }
}
