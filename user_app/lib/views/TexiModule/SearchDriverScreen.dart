import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:ravelgo_user_app/components/SafeGoogleMap.dart';
import 'package:ravelgo_user_app/services/api_client.dart';
import 'package:ravelgo_user_app/services/booking_api.dart';
import 'package:ravelgo_user_app/services/payments_api.dart';
import 'package:ravelgo_user_app/services/realtime_service.dart';
import 'package:ravelgo_user_app/services/settings_api.dart';
import 'package:ravelgo_user_app/services/paystack_service.dart';
import 'package:ravelgo_user_app/services/trips_api.dart';
import 'package:ravelgo_user_app/config/currency.dart';
import 'package:ravelgo_user_app/theme/app_theme.dart';

/// Shown after a trip is actually created on the backend. Reflects the real
/// result: a driver may already have been OFFERED the trip (they still have
/// to explicitly accept — see backend/src/services/matching.ts), or the
/// request may be waiting for a driver to come online at all (REQUESTED).
/// Either way this screen keeps showing "looking for a driver" until the
/// offered driver actually accepts (status becomes MATCHED) — it never
/// presents a driver as assigned before the backend confirms an acceptance.
class SearchDriverScreen extends StatefulWidget {
  final Trip trip;
  const SearchDriverScreen({super.key, required this.trip});

  @override
  State<SearchDriverScreen> createState() => _SearchDriverScreenState();
}

class _SearchDriverScreenState extends State<SearchDriverScreen> {
  final RealtimeService _rt = RealtimeService();

  // Mutable — a driver can now be matched well after this screen was built
  // (see backend/src/services/matching.ts's matchPendingTrips, triggered by a
  // driver going online), not just at trip-creation time. The 'trip:status'
  // WebSocket message that reports that only ever carries a status string,
  // never driver/vehicle details, so _refreshIfNewlyMatched() re-fetches the
  // full trip and replaces this rather than trying to patch fields in place.
  late Trip _trip = widget.trip;
  Trip get trip => _trip;

  // Live state, seeded from the created trip and updated over the WebSocket.
  late String _status = trip.status;
  bool _live = false;
  DateTime? _lastLocationAt;

  // EI-2: the driver's live position while MATCHED/IN_PROGRESS, polled the
  // same way DeliveryTrackingScreen polls a courier's — a WebSocket push
  // (case 'location' in _onMessage) updates this immediately when connected,
  // and the poll is the fallback for a client not holding one (mirrors the
  // backend's own driver-location route doc comment). Presence is the exact
  // LIVE/STALE value the backend computes (locationFreshness), never
  // recomputed client-side, so it can never disagree with the admin Live Map.
  Timer? _driverLocationPoll;
  double? _driverLat;
  double? _driverLng;
  String? _driverPresence;
  DateTime? _driverLocationUpdatedAt;

  // Reports the rider's own position back to the backend — only while a
  // driver is assigned or the ride is under way (see _syncLocationPing).
  // Before that (REQUESTED) or after (COMPLETED/CANCELLED/DISPUTED) there is
  // nothing for ops to monitor, and the backend refuses the ping anyway.
  Timer? _locationTimer;

  // Post-trip rating.
  int _rating = 0;
  bool _ratingBusy = false;
  bool _rated = false;

  // Cancellation.
  bool _cancelBusy = false;

  // Payment for the completed trip (P0 #1).
  bool _paid = false;
  bool _payBusy = false;

  // Server-authoritative cash cap (default ₦15,000) — fetched once the trip
  // completes so the button row reflects real backend rules, not a guess.
  // Falls back to the documented default if the call hasn't returned yet or
  // fails, which can only ever be equal to or narrower than the real limit.
  PaymentSettings _paymentSettings = PaymentSettings.fallback();

  Future<void> _loadPaymentSettings() async {
    try {
      final settings = await SettingsApi.paymentSettings();
      if (mounted) setState(() => _paymentSettings = settings);
    } catch (_) {
      // Keep the conservative fallback — the backend still enforces the real
      // rule regardless of what this screen shows.
    }
  }

  /// Pay for the completed trip. CARD opens a backend-issued Paystack
  /// checkout page; WALLET settles from the rider's balance; CASH settles
  /// instantly (handed to the driver) but only below the cash limit — the
  /// backend rejects it above the limit even if this button were somehow
  /// shown. If the driver already charged the trip the backend returns 409,
  /// which we treat as paid.
  Future<void> _payTrip(String method) async {
    if (_payBusy) return;
    setState(() => _payBusy = true);
    try {
      if (method == 'CARD') {
        final authorizationUrl = await PaymentsApi.payTripWithCard(trip.id);
        await PaystackService.openCheckout(authorizationUrl);
        // Opening the checkout page only means the browser launched — unlike
        // the removed Stripe PaymentSheet, it is not a signal the rider
        // actually completed payment. The trip only becomes PAID once the
        // signed Paystack webhook confirms it backend-side, which this app
        // has no way to observe directly while the browser tab is open.
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Complete your payment in the browser, then return here.')),
        );
        return;
      } else if (method == 'CASH') {
        await PaymentsApi.payTripWithCash(trip.id);
      } else {
        await PaymentsApi.payTripWithWallet(trip.id);
      }
      if (!mounted) return;
      setState(() => _paid = true);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Payment complete.')));
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.statusCode == 409) {
        // Already charged (e.g. the driver settled it) — nothing more to pay.
        setState(() => _paid = true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _payBusy = false);
    }
  }

  Widget _paymentSection() {
    final cashAllowed = _paymentSettings.allowsCash(trip.fare);
    return Column(
      children: [
        Row(
          children: [
            const Text('Amount due', style: TextStyle(fontWeight: FontWeight.w500)),
            const Spacer(),
            Text(Currency.format(trip.fare), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        const SizedBox(height: 10),
        if (!cashAllowed) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppColors.warning.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
            child: Text(
              'Cash payment isn\'t available for fares above ${Currency.format(_paymentSettings.cashPaymentLimit, decimals: 0)}.',
              style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
            ),
          ),
          const SizedBox(height: 10),
        ],
        if (_payBusy)
          const Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator())
        else
          Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _payTrip('WALLET'),
                      icon: const Icon(Icons.account_balance_wallet_outlined),
                      label: const Text('Pay with wallet'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _payTrip('CARD'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.credit_card),
                      label: const Text('Pay by card'),
                    ),
                  ),
                ],
              ),
              if (cashAllowed) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _payTrip('CASH'),
                    style: OutlinedButton.styleFrom(foregroundColor: AppColors.success, side: const BorderSide(color: AppColors.success)),
                    icon: const Icon(Icons.payments_outlined),
                    label: const Text('Pay with cash'),
                  ),
                ),
              ],
            ],
          ),
        const SizedBox(height: 16),
      ],
    );
  }

  /// Cancel the trip on the backend (P0 #7). Only allowed while the trip is
  /// still REQUESTED or MATCHED — the backend enforces this too. On success the
  /// screen reflects the real CANCELLED status instead of pretending locally.
  Future<void> _cancelTrip() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel this trip?'),
        content: const Text('Your driver request will be withdrawn.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep trip')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cancel trip', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _cancelBusy = true);
    try {
      await BookingApi.cancelTrip(trip.id);
      if (!mounted) return;
      setState(() => _status = 'CANCELLED');
      _syncLocationPing();
      _syncDriverLocationPoll();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _cancelBusy = false);
    }
  }

  Future<void> _submitRating(int stars) async {
    setState(() {
      _rating = stars;
      _ratingBusy = true;
    });
    try {
      await TripsApi.rate(trip.id, stars);
      if (!mounted) return;
      setState(() => _rated = true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _ratingBusy = false);
    }
  }

  Widget _ratingSection() {
    if (_rated) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text('Thanks for rating your driver!',
            textAlign: TextAlign.center, style: TextStyle(color: AppColors.success, fontWeight: FontWeight.w600)),
      );
    }
    return Column(
      children: [
        const Text('Rate your driver', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(5, (i) {
            final star = i + 1;
            return IconButton(
              iconSize: 34,
              onPressed: _ratingBusy ? null : () => _submitRating(star),
              icon: Icon(star <= _rating ? Icons.star : Icons.star_border, color: AppColors.warning),
            );
          }),
        ),
        if (_ratingBusy) const Padding(padding: EdgeInsets.all(4), child: CircularProgressIndicator()),
      ],
    );
  }

  bool get _matched => _status == 'MATCHED' && (trip.driverName?.isNotEmpty ?? false);
  bool get _inProgress => _status == 'IN_PROGRESS';
  bool get _completed => _status == 'COMPLETED';
  bool get _cancelled => _status == 'CANCELLED' || _status == 'DISPUTED';
  // Cancellation is only offered before the ride is under way — mirrors the
  // backend's riderMayCancel (REQUESTED, OFFERED, or MATCHED).
  bool get _cancellable => _status == 'REQUESTED' || _status == 'OFFERED' || _status == 'MATCHED';

  @override
  void initState() {
    super.initState();
    _startRealtime();
    _loadPaymentSettings();
    _syncLocationPing();
    _syncDriverLocationPoll();
  }

  /// Start/stop the rider location ping to match the current trip status —
  /// called on entry and every time _status changes (trip:status message,
  /// or the local optimistic update in _cancelTrip).
  void _syncLocationPing() {
    final trackable = _status == 'MATCHED' || _status == 'IN_PROGRESS';
    if (trackable && _locationTimer == null) {
      _pingLocation();
      _locationTimer = Timer.periodic(const Duration(seconds: 15), (_) => _pingLocation());
    } else if (!trackable && _locationTimer != null) {
      _locationTimer?.cancel();
      _locationTimer = null;
    }
  }

  /// Start/stop polling the driver's position for the map, same lifecycle as
  /// the rider-location ping above. A WebSocket 'location' push (see
  /// _onMessage) updates the map immediately when connected; this poll is
  /// what keeps it current for a client not holding one, exactly as the
  /// backend route's own doc comment describes it.
  void _syncDriverLocationPoll() {
    final trackable = _status == 'MATCHED' || _status == 'IN_PROGRESS';
    if (trackable && _driverLocationPoll == null) {
      _pollDriverLocation();
      _driverLocationPoll = Timer.periodic(const Duration(seconds: 10), (_) => _pollDriverLocation());
    } else if (!trackable && _driverLocationPoll != null) {
      _driverLocationPoll?.cancel();
      _driverLocationPoll = null;
    }
  }

  Future<void> _pollDriverLocation() async {
    try {
      final loc = await TripsApi.driverLocation(trip.id);
      if (!mounted || loc == null) return;
      setState(() {
        _driverLat = loc.lat;
        _driverLng = loc.lng;
        _driverPresence = loc.presence;
        _driverLocationUpdatedAt = loc.updatedAt;
      });
    } catch (_) {
      // Best-effort — a missed poll just means the map keeps its last known
      // position until the next tick or WebSocket push.
    }
  }

  Future<void> _pingLocation() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return;
      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      await TripsApi.pingLocation(trip.id, pos.latitude, pos.longitude);
    } catch (_) {
      // Best-effort: a failed fix/ping just means no update this tick — the
      // admin Live Map shows this rider as STALE rather than the app ever
      // blocking on a missed location.
    }
  }

  Future<void> _startRealtime() async {
    if (!RealtimeService.isConfigured) return;
    final ok = await _rt.connect(
      onMessage: _onMessage,
      onDone: () {
        if (mounted) setState(() => _live = false);
      },
    );
    if (ok) _rt.subscribe(trip.id);
  }

  Future<void> _refreshTrip() async {
    try {
      final fresh = await TripsApi.byId(widget.trip.id);
      if (!mounted) return;
      setState(() => _trip = fresh);
    } catch (_) {
      // Best-effort — the status banner already reflects MATCHED from the
      // WebSocket message; only the driver-details card is missing until a
      // retry (the next poll cycle, or a pull-to-refresh path if one exists).
    }
  }

  void _onMessage(Map<String, dynamic> m) {
    if (!mounted) return;
    switch (m['type']) {
      case 'subscribed':
        setState(() => _live = true);
        break;
      case 'trip:status':
        if ('${m['tripId']}' == trip.id) {
          final newStatus = '${m['status']}';
          setState(() => _status = newStatus);
          _syncLocationPing();
          _syncDriverLocationPoll();
          // This message never carries driver/vehicle details — only a
          // late match (see backend's matchPendingTrips) reaches this screen
          // as a bare status flip with nothing else to render, so a matched
          // trip whose local copy still has no driver needs a real refetch.
          if (newStatus == 'MATCHED' && (trip.driverName == null || trip.driverName!.isEmpty)) {
            _refreshTrip();
          }
        }
        break;
      case 'location':
        if ('${m['tripId']}' == trip.id) {
          final lat = m['lat'];
          final lng = m['lng'];
          setState(() {
            _lastLocationAt = DateTime.now();
            // A push arriving right now is definitionally fresh — no need to
            // wait for the next poll tick to reflect it as LIVE.
            if (lat is num && lng is num) {
              _driverLat = lat.toDouble();
              _driverLng = lng.toDouble();
              _driverPresence = 'LIVE';
              _driverLocationUpdatedAt = DateTime.now();
            }
          });
        }
        break;
    }
  }

  @override
  void dispose() {
    _rt.dispose();
    _locationTimer?.cancel();
    _driverLocationPoll?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // EI-2: a real map, not a decorative backdrop — pickup/dropoff pins
          // plus the driver's live position once one is available, same
          // approach as DeliveryTrackingScreen's map for a delivery.
          Positioned.fill(child: _map()),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: _buildSearchBar(),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              decoration: const BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                boxShadow: [BoxShadow(color: AppColors.border, blurRadius: 10)],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildStatusBanner(),
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        _buildTripInfo(),
                        const SizedBox(height: 16),
                        if (_completed) ...[
                          if (!_paid) _paymentSection(),
                          _ratingSection(),
                        ] else if (_cancellable)
                          _buildCancelButton(),
                      ],
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

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [const BoxShadow(color: AppColors.border, blurRadius: 8)],
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
            onPressed: () => Navigator.pop(context),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(trip.destination, style: const TextStyle(fontSize: 16))),
        ],
      ),
    );
  }

  Color _bannerColor() {
    if (_cancelled) return AppColors.error;
    if (_completed) return AppColors.success;
    if (_inProgress) return AppColors.primaryDark;
    if (_matched) return AppColors.success;
    return AppColors.primary;
  }

  Widget _buildStatusBanner() {
    late final Widget content;
    if (_completed) {
      content = Column(children: const [
        Icon(Icons.flag, color: Colors.white, size: 32),
        SizedBox(height: 8),
        Text('Trip completed', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
        SizedBox(height: 4),
        Text('Thanks for riding with RavelGo.', style: TextStyle(color: Colors.white70, fontSize: 13)),
      ]);
    } else if (_cancelled) {
      content = Column(children: const [
        Icon(Icons.cancel, color: Colors.white, size: 32),
        SizedBox(height: 8),
        Text('Trip cancelled', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
      ]);
    } else if (_inProgress) {
      content = Column(children: [
        const Icon(Icons.directions_car, color: Colors.white, size: 32),
        const SizedBox(height: 8),
        Text('On the way — trip in progress${trip.driverName != null ? ' with ${trip.driverName}' : ''}',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
        if (_lastLocationAt != null) ...[
          const SizedBox(height: 4),
          const Text('Driver location updating live', style: TextStyle(color: Colors.white70, fontSize: 12)),
        ],
      ]);
    } else if (_matched) {
      content = Column(children: [
        const Icon(Icons.check_circle, color: Colors.white, size: 32),
        const SizedBox(height: 8),
        Text('Driver found: ${trip.driverName}',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 4),
        const Text('Your driver is on the way.', style: TextStyle(color: Colors.white70, fontSize: 13)),
      ]);
    } else {
      content = Column(children: const [
        SizedBox(height: 28, width: 28, child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white)),
        SizedBox(height: 10),
        Text('Looking for a driver…',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
        SizedBox(height: 4),
        Text('No driver is available right now — we\'ll keep trying.',
            textAlign: TextAlign.center, style: TextStyle(color: Colors.white70, fontSize: 13)),
      ]);
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
      decoration: BoxDecoration(
        color: _bannerColor(),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          content,
          if (_live) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                Icon(Icons.circle, color: Colors.white, size: 8),
                SizedBox(width: 6),
                Text('Live', style: TextStyle(color: Colors.white70, fontSize: 11)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTripInfo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Your Trip", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        const SizedBox(height: 8),
        Row(
          children: [
            Image.asset('assets/ic_pickup.png', width: 24, height: 24),
            const SizedBox(width: 8),
            Expanded(child: Text(trip.pickup, style: const TextStyle(fontSize: 16))),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Image.asset('assets/ic_destination.png', width: 24, height: 24),
            const SizedBox(width: 8),
            Expanded(child: Text(trip.destination, style: const TextStyle(fontSize: 16))),
          ],
        ),
        const SizedBox(height: 15),
        Row(
          children: [
            const Text('Fare', style: TextStyle(fontWeight: FontWeight.w500)),
            const Spacer(),
            Text(Currency.format(trip.fare),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        if (_matched || _inProgress) ...[
          const SizedBox(height: 16),
          _buildDriverCard(),
          _locationFreshnessLabel(),
        ],
      ],
    );
  }

  /// Pickup/dropoff pins, plus the driver's live position once reported.
  /// Falls back to a plain background (never a fake decorative image) if a
  /// trip somehow has no coordinates at all.
  Widget _map() {
    final markers = <Marker>{};
    if (trip.pickupLat != null && trip.pickupLng != null) {
      markers.add(Marker(
        markerId: const MarkerId('pickup'),
        position: LatLng(trip.pickupLat!, trip.pickupLng!),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        infoWindow: const InfoWindow(title: 'Pickup'),
      ));
    }
    if (trip.dropoffLat != null && trip.dropoffLng != null) {
      markers.add(Marker(
        markerId: const MarkerId('dropoff'),
        position: LatLng(trip.dropoffLat!, trip.dropoffLng!),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        infoWindow: const InfoWindow(title: 'Destination'),
      ));
    }
    if (_driverLat != null && _driverLng != null) {
      markers.add(Marker(
        markerId: const MarkerId('driver'),
        position: LatLng(_driverLat!, _driverLng!),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        infoWindow: const InfoWindow(title: 'Driver'),
      ));
    }
    if (markers.isEmpty) return Container(color: AppColors.background);

    final center = (_driverLat != null && _driverLng != null) ? LatLng(_driverLat!, _driverLng!) : markers.first.position;
    return SafeGoogleMap(
      initialCameraPosition: CameraPosition(target: center, zoom: 14),
      markers: markers,
      myLocationButtonEnabled: false,
      zoomControlsEnabled: false,
    );
  }

  /// LIVE / STALE / no-report-yet — the exact same three-state freshness
  /// model DeliveryTrackingScreen shows for a courier (and the admin Live
  /// Map behind both), reusing the backend's own presence value rather than
  /// recomputing it here.
  Widget _locationFreshnessLabel() {
    String text;
    IconData icon;
    Color color;
    if (_driverPresence == 'LIVE') {
      final seconds = _driverLocationUpdatedAt == null
          ? 0
          : DateTime.now().difference(_driverLocationUpdatedAt!).inSeconds.clamp(0, 999);
      text = 'Driver location updated ${seconds}s ago';
      icon = Icons.circle;
      color = AppColors.success;
    } else if (_driverPresence == 'STALE') {
      final minutes = _driverLocationUpdatedAt == null
          ? 0
          : DateTime.now().difference(_driverLocationUpdatedAt!).inMinutes;
      text = "Driver location hasn't updated in ${minutes}m";
      icon = Icons.warning_amber_rounded;
      color = AppColors.textMuted;
    } else {
      text = 'Driver location is temporarily unavailable';
      icon = Icons.location_off_outlined;
      color = AppColors.textMuted;
    }
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(text, style: TextStyle(fontSize: 12.5, color: color)),
        ],
      ),
    );
  }

  /// The matched driver's summary — shown once a driver is assigned so MATCHED
  /// results in a visible driver card rather than an endless spinner (P0 #8).
  /// All fields come from the backend's safe trip serialization.
  Widget _buildDriverCard() {
    final name = trip.driverName ?? 'Your driver';
    final rating = trip.driverRating;
    final vehicle = trip.vehicleLabel;
    final plate = trip.vehiclePlate;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 22,
            backgroundColor: AppColors.primary,
            child: Icon(Icons.person, color: AppColors.surface),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                if (vehicle != null && vehicle.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(vehicle, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                  ),
                if (plate != null && plate.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(plate,
                        style: const TextStyle(fontWeight: FontWeight.w600, letterSpacing: 1, fontSize: 13)),
                  ),
              ],
            ),
          ),
          if (rating != null)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.star, color: AppColors.warning, size: 18),
                const SizedBox(width: 2),
                Text(rating.toStringAsFixed(1), style: const TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildCancelButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _cancelBusy ? null : _cancelTrip,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        child: _cancelBusy
            ? const SizedBox(
                height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : Text(_matched ? 'Cancel trip' : 'Cancel request'),
      ),
    );
  }
}
