import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:ravelgo_user/services/api_client.dart';
import 'package:ravelgo_user/services/trip_service.dart';
import 'package:ravelgo_user/views/HomeView/home.dart';
import 'package:ravelgo_user/views/TexiModule/cancel_ride_screen.dart';

/// Shown right after a trip is requested. The backend matches a driver
/// synchronously at creation time (see backend/src/services/matching.ts) —
/// there is no queue or later retry — so this screen either already knows
/// the assigned driver, or polls briefly in case matching data changes
/// (e.g. the trip gets cancelled elsewhere) while the rider waits.
class SearchDriverScreen extends StatefulWidget {
  final Map<String, dynamic> trip;

  const SearchDriverScreen({super.key, required this.trip});

  @override
  State<SearchDriverScreen> createState() => _SearchDriverScreenState();
}

class _SearchDriverScreenState extends State<SearchDriverScreen> {
  late Map<String, dynamic> _trip;
  Timer? _pollTimer;
  bool _cancelling = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _trip = widget.trip;
    _maybeStartPolling();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  bool get _isMatched => _trip['driverId'] != null;
  String get _status => _trip['status'] as String? ?? 'REQUESTED';

  void _maybeStartPolling() {
    _pollTimer?.cancel();
    if (_status != 'REQUESTED') return;
    _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) => _refresh());
  }

  Future<void> _refresh() async {
    try {
      final trip = await TripService().getTrip(_trip['id'] as String);
      if (!mounted) return;
      setState(() {
        _trip = trip;
        _error = null;
      });
      if (_status != 'REQUESTED') _pollTimer?.cancel();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (_) {
      // A transient poll failure isn't worth interrupting the wait screen
      // over — the next tick will try again.
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
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          GoogleMap(
            onMapCreated: (controller) {},
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
                          if (_isMatched) _buildMatchedCard() else _buildSearchingCard(),
                          if (_error != null) ...[
                            const SizedBox(height: 10),
                            Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
                          ],
                        ],
                      ),
                    ),
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

  Widget _buildTerminalState({required IconData icon, required String title, required String buttonLabel}) {
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
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const HomePage())),
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

  Widget _buildMatchedCard() {
    final driver = _trip['driver'] as Map<String, dynamic>?;
    final user = driver?['user'] as Map<String, dynamic>?;
    final name = user != null ? '${user['firstName'] ?? ''} ${user['lastName'] ?? ''}'.trim() : 'Your driver';
    final rating = (driver?['rating'] as num?)?.toStringAsFixed(2) ?? '—';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
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
        ),
        const SizedBox(height: 16),
        Text('NGN ${_formatFare(_trip['estimatedFare'])}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        const Text("Your driver is on the way", style: TextStyle(fontSize: 13, color: Colors.grey)),
      ],
    );
  }

  Widget _buildCancelButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _cancelling ? null : _openCancelSheet,
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
