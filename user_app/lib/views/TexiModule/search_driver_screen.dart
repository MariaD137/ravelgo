import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:ravelgo_user/services/api_client.dart';
import 'package:ravelgo_user/services/trip_service.dart';
import 'package:ravelgo_user/views/HomeView/home.dart';
import 'package:ravelgo_user/views/OtherViews/payment_view.dart';
import 'package:ravelgo_user/views/TexiModule/cancel_ride_screen.dart';

/// Shown right after a trip is requested, and carries the rider through the
/// entire trip lifecycle from there — matching, live tracking once the
/// driver starts the trip, and completion. The backend matches a driver
/// synchronously at creation time (see backend/src/services/matching.ts) —
/// there is no queue or later retry — so the REQUESTED phase here is either
/// already resolved, or polls briefly in case matching data changes (e.g.
/// the trip gets cancelled elsewhere) while the rider waits. From MATCHED
/// onward this keeps polling GET /trips/:id (and, once IN_PROGRESS, the
/// driver's last-known location) until the trip reaches a terminal status.
class SearchDriverScreen extends StatefulWidget {
  final Map<String, dynamic> trip;

  const SearchDriverScreen({super.key, required this.trip});

  @override
  State<SearchDriverScreen> createState() => _SearchDriverScreenState();
}

class _SearchDriverScreenState extends State<SearchDriverScreen> {
  static const _nonTerminalStatuses = {'REQUESTED', 'MATCHED', 'IN_PROGRESS'};

  late Map<String, dynamic> _trip;
  Timer? _pollTimer;
  Timer? _locationTimer;
  String? _error;
  LatLng? _driverLatLng;
  GoogleMapController? _mapController;

  @override
  void initState() {
    super.initState();
    _trip = widget.trip;
    _maybeStartPolling();
    _maybeStartLocationPolling();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _locationTimer?.cancel();
    super.dispose();
  }

  bool get _isMatched => _trip['driverId'] != null;
  String get _status => _trip['status'] as String? ?? 'REQUESTED';

  void _maybeStartPolling() {
    _pollTimer?.cancel();
    if (!_nonTerminalStatuses.contains(_status)) return;
    _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) => _refresh());
  }

  void _maybeStartLocationPolling() {
    _locationTimer?.cancel();
    if (_status != 'MATCHED' && _status != 'IN_PROGRESS') return;
    _locationTimer = Timer.periodic(const Duration(seconds: 5), (_) => _refreshDriverLocation());
    _refreshDriverLocation();
  }

  Future<void> _refresh() async {
    try {
      final trip = await TripService().getTrip(_trip['id'] as String);
      if (!mounted) return;
      final previousStatus = _status;
      setState(() {
        _trip = trip;
        _error = null;
      });
      if (!_nonTerminalStatuses.contains(_status)) {
        _pollTimer?.cancel();
        _locationTimer?.cancel();
      } else if (_status != previousStatus) {
        _maybeStartLocationPolling();
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (_) {
      // A transient poll failure isn't worth interrupting the wait screen
      // over — the next tick will try again.
    }
  }

  Future<void> _refreshDriverLocation() async {
    try {
      final location = await TripService().getDriverLocation(_trip['id'] as String);
      if (!mounted || location == null) return;
      final lat = (location['lat'] as num?)?.toDouble();
      final lng = (location['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) return;
      final latLng = LatLng(lat, lng);
      setState(() => _driverLatLng = latLng);
      _mapController?.animateCamera(CameraUpdate.newLatLng(latLng));
    } catch (_) {
      // Location is best-effort — the trip's own status polling is the
      // source of truth for the rider's flow, this just enriches it.
    }
  }

  Future<void> _openCancelSheet() async {
    final cancelled = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return FractionallySizedBox(
          heightFactor: 0.8,
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            child: CancelRideScreen(tripId: _trip['id'] as String),
          ),
        );
      },
    );
    if (cancelled == true && mounted) {
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const HomePage()));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_status == 'CANCELLED') {
      return _buildTerminalState(
        icon: Icons.cancel_outlined,
        title: 'This trip was cancelled',
        buttonLabel: 'Back to home',
        onPressed: () => Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const HomePage())),
      );
    }
    if (_status == 'COMPLETED' || _status == 'DISPUTED') {
      return _buildTerminalState(
        icon: Icons.check_circle_outline,
        title: 'Trip complete',
        subtitle: 'NGN ${_formatFare(_trip['finalFare'] ?? _trip['estimatedFare'])}',
        buttonLabel: 'View receipt / Pay',
        onPressed: () => Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const PaymentView())),
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          GoogleMap(
            onMapCreated: (controller) => _mapController = controller,
            initialCameraPosition: CameraPosition(
              target: _driverLatLng ?? const LatLng(6.5244, 3.3792),
              zoom: 14,
            ),
            myLocationEnabled: true,
            zoomControlsEnabled: false,
            markers: _driverLatLng == null
                ? <Marker>{}
                : <Marker>{
                    Marker(
                      markerId: const MarkerId('driver'),
                      position: _driverLatLng!,
                      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueYellow),
                    ),
                  },
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: _buildTopBar(),
            ),
          ),
          DraggableScrollableSheet(
            initialChildSize: 0.4,
            minChildSize: 0.3,
            maxChildSize: 0.65,
            builder: (context, scrollController) {
              return Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                  boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10)],
                ),
                child: Column(
                  children: [
                    Expanded(
                      child: ListView(
                        controller: scrollController,
                        padding: const EdgeInsets.all(20),
                        children: [
                          if (_status == 'IN_PROGRESS')
                            _buildInProgressCard()
                          else if (_isMatched)
                            _buildMatchedCard()
                          else
                            _buildSearchingCard(),
                          if (_error != null) ...[
                            const SizedBox(height: 10),
                            Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
                          ],
                        ],
                      ),
                    ),
                    // A trip already IN_PROGRESS can't be cancelled by the
                    // rider through this flow — see VALID_TRIP_TRANSITIONS
                    // in trips.routes.ts; only REQUESTED/MATCHED allow it
                    // through the normal cancel path.
                    if (_status != 'IN_PROGRESS')
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: _buildCancelButton(),
                      ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTerminalState({
    required IconData icon,
    required String title,
    String? subtitle,
    required String buttonLabel,
    required VoidCallback onPressed,
  }) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 56, color: Colors.grey),
                const SizedBox(height: 16),
                Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600), textAlign: TextAlign.center),
                if (subtitle != null) ...[
                  const SizedBox(height: 8),
                  Text(subtitle, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                ],
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: onPressed,
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.yellow[700], foregroundColor: Colors.black),
                  child: Text(buttonLabel),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      height: 48,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 8)],
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${_trip['pickup'] ?? ''} → ${_trip['destination'] ?? ''}',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchingCard() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(35),
          decoration: BoxDecoration(color: Colors.yellow[100], shape: BoxShape.circle),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black87),
              ),
              SizedBox(height: 12),
              Text("Finding a driver...", style: TextStyle(fontWeight: FontWeight.w500, fontSize: 14)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'NGN ${_formatFare(_trip['estimatedFare'])}',
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        const Text(
          "No drivers are online right now — you can keep waiting or cancel.",
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
      ],
    );
  }

  Widget _buildDriverHeader() {
    final driver = _trip['driver'] as Map<String, dynamic>?;
    final user = driver?['user'] as Map<String, dynamic>?;
    final name = user != null ? '${user['firstName'] ?? ''} ${user['lastName'] ?? ''}'.trim() : 'Your driver';
    final rating = (driver?['rating'] as num?)?.toStringAsFixed(2) ?? '—';

    return Row(
      children: [
        const CircleAvatar(radius: 28, backgroundColor: Colors.black12, child: Icon(Icons.person, color: Colors.black54)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name.isEmpty ? 'Your driver' : name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
              Row(
                children: [
                  const Icon(Icons.star, color: Colors.green, size: 16),
                  const SizedBox(width: 4),
                  Text('$rating rating', style: const TextStyle(fontSize: 13, color: Colors.black87)),
                ],
              ),
            ],
          ),
        ),
        const Icon(Icons.verified, color: Colors.amber),
      ],
    );
  }

  Widget _buildMatchedCard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildDriverHeader(),
        const SizedBox(height: 16),
        Text('NGN ${_formatFare(_trip['estimatedFare'])}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        const Text("Your driver is on the way", style: TextStyle(fontSize: 13, color: Colors.grey)),
      ],
    );
  }

  Widget _buildInProgressCard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildDriverHeader(),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
          decoration: BoxDecoration(color: Colors.green[50], borderRadius: BorderRadius.circular(10)),
          child: const Row(
            children: [
              Icon(Icons.directions_car, color: Colors.green, size: 18),
              SizedBox(width: 8),
              Text("Trip in progress — heading to your destination", style: TextStyle(fontSize: 13, color: Colors.black87)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text('NGN ${_formatFare(_trip['estimatedFare'])}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        const Text("Estimated fare — final fare is calculated when the trip ends", style: TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }

  Widget _buildCancelButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _openCancelSheet,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.yellow[700],
          foregroundColor: Colors.black,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        child: const Text("Cancel request"),
      ),
    );
  }

  String _formatFare(dynamic value) {
    if (value is num) return value.toStringAsFixed(0);
    return '0';
  }
}
