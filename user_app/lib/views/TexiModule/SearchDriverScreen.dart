import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:ravelgo_user_app/components/SafeGoogleMap.dart';
import 'package:ravelgo_user_app/services/api_client.dart';
import 'package:ravelgo_user_app/services/booking_api.dart';
import 'package:ravelgo_user_app/services/payments_api.dart';
import 'package:ravelgo_user_app/services/realtime_service.dart';
import 'package:ravelgo_user_app/services/stripe_service.dart';
import 'package:ravelgo_user_app/services/trips_api.dart';
import 'package:ravelgo_user_app/config/currency.dart';
import 'package:ravelgo_user_app/theme/app_theme.dart';

/// Shown after a trip is actually created on the backend. Reflects the real
/// result: either a driver was auto-matched (status MATCHED) or the request is
/// waiting for a driver to come online (status REQUESTED).
class SearchDriverScreen extends StatefulWidget {
  final Trip trip;
  const SearchDriverScreen({super.key, required this.trip});

  @override
  State<SearchDriverScreen> createState() => _SearchDriverScreenState();
}

class _SearchDriverScreenState extends State<SearchDriverScreen> {
  final RealtimeService _rt = RealtimeService();

  Trip get trip => widget.trip;

  // Live state, seeded from the created trip and updated over the WebSocket.
  late String _status = trip.status;
  bool _live = false;
  DateTime? _lastLocationAt;

  // Post-trip rating.
  int _rating = 0;
  bool _ratingBusy = false;
  bool _rated = false;

  // Cancellation.
  bool _cancelBusy = false;

  // Payment for the completed trip (P0 #1).
  bool _paid = false;
  bool _payBusy = false;

  /// Pay for the completed trip. CARD confirms a backend PaymentIntent in the
  /// Stripe PaymentSheet; WALLET settles from the rider's balance. If the driver
  /// already charged the trip the backend returns 409, which we treat as paid.
  Future<void> _payTrip(String method) async {
    if (_payBusy) return;
    if (method == 'CARD' && !StripeService.isConfigured) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Card payments are not configured yet.')),
      );
      return;
    }
    setState(() => _payBusy = true);
    try {
      if (method == 'CARD') {
        final clientSecret = await PaymentsApi.payTripWithCard(trip.id);
        await StripeService.presentPaymentSheet(clientSecret: clientSecret);
      } else {
        await PaymentsApi.payTripWithWallet(trip.id);
      }
      if (!mounted) return;
      setState(() => _paid = true);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Payment complete.')));
    } on StripeException catch (_) {
      // Rider cancelled or the card sheet failed — nothing was charged.
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
        if (_payBusy)
          const Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator())
        else
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
                    foregroundColor: AppColors.textPrimary,
                  ),
                  icon: const Icon(Icons.credit_card),
                  label: const Text('Pay by card'),
                ),
              ),
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
  // backend's riderMayCancel (REQUESTED or MATCHED only).
  bool get _cancellable => _status == 'REQUESTED' || _status == 'MATCHED';

  @override
  void initState() {
    super.initState();
    _startRealtime();
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

  void _onMessage(Map<String, dynamic> m) {
    if (!mounted) return;
    switch (m['type']) {
      case 'subscribed':
        setState(() => _live = true);
        break;
      case 'trip:status':
        if ('${m['tripId']}' == trip.id) setState(() => _status = '${m['status']}');
        break;
      case 'location':
        if ('${m['tripId']}' == trip.id) setState(() => _lastLocationAt = DateTime.now());
        break;
    }
  }

  @override
  void dispose() {
    _rt.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          SafeGoogleMap(
            initialCameraPosition: const CameraPosition(
              target: LatLng(6.5244, 3.3792),
              zoom: 14,
            ),
            myLocationEnabled: true,
            zoomControlsEnabled: false,
          ),
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
        ],
      ],
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
