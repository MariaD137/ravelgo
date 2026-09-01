import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:ravelgo_user_app/components/SafeGoogleMap.dart';
import 'package:ravelgo_user_app/services/realtime_service.dart';
import 'package:ravelgo_user_app/services/trips_api.dart';
import 'package:ravelgo_user_app/views/TexiModule/CancelRideScreen.dart';
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
                        if (_completed) _ratingSection() else _buildCancelButton(),
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
      ],
    );
  }

  Widget _buildCancelButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: () {
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (context) => FractionallySizedBox(
              heightFactor: 0.8,
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                child: const CancelRideScreen(),
              ),
            ),
          );
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.textPrimary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        child: const Text("Cancel request"),
      ),
    );
  }
}
