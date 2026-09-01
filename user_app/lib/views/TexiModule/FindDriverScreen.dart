import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:ravelgo_user_app/components/SafeGoogleMap.dart';
import 'package:ravelgo_user_app/services/api_client.dart';
import 'package:ravelgo_user_app/services/booking_api.dart';
import 'package:ravelgo_user_app/config/currency.dart';
import 'package:ravelgo_user_app/views/TexiModule/SearchDriverScreen.dart';
import 'package:ravelgo_user_app/theme/app_theme.dart';

class FindDriverScreen extends StatefulWidget {
  final String? pickup;
  final String? destination;
  final String paymentMethod;
  // Real trip metrics from the destination selection on SelectRide, when available.
  final double? distanceKm;
  final double? durationMinutes;
  // Pickup + dropoff coordinates — required by the backend, which computes the
  // authoritative distance/fare from them (the client no longer sends distance).
  final double? pickupLat;
  final double? pickupLng;
  final double? dropoffLat;
  final double? dropoffLng;
  const FindDriverScreen({
    super.key,
    this.pickup,
    this.destination,
    this.paymentMethod = 'Card',
    this.distanceKm,
    this.durationMinutes,
    this.pickupLat,
    this.pickupLng,
    this.dropoffLat,
    this.dropoffLng,
  });

  @override
  State<FindDriverScreen> createState() => _FindDriverScreenState();
}

class _FindDriverScreenState extends State<FindDriverScreen> {
  Set<Marker> _markers = {};

  String get _pickup =>
      (widget.pickup != null && widget.pickup!.trim().isNotEmpty)
          ? widget.pickup!.trim()
          : 'Current location';

  // Use the rider's map-selected distance/duration when present, else the
  // placeholder (e.g. if they skipped dropping a pin).
  double get _distanceKm => widget.distanceKm ?? BookingApi.placeholderDistanceKm;
  double get _durationMinutes => widget.durationMinutes ?? BookingApi.placeholderDurationMinutes;

  FareQuote? _quote;
  String? _quoteError;
  bool _quoteLoading = true;
  bool _requesting = false;

  String get _destination =>
      (widget.destination != null && widget.destination!.trim().isNotEmpty)
          ? widget.destination!.trim()
          : 'Destination';

  @override
  void initState() {
    super.initState();
    _loadMarkers();
    _loadQuote();
  }

  Future<void> _loadQuote() async {
    setState(() {
      _quoteLoading = true;
      _quoteError = null;
    });
    try {
      final q = await BookingApi.quote(
        distanceKm: _distanceKm,
        durationMinutes: _durationMinutes,
      );
      if (!mounted) return;
      setState(() {
        _quote = q;
        _quoteLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _quoteError = e is ApiException && e.statusCode == 409
            ? 'Pricing isn\'t set up yet — please try later.'
            : e.toString();
        _quoteLoading = false;
      });
    }
  }

  Future<void> _findDriver() async {
    // The backend computes fare from coordinates, so they're required. If the
    // rider reached here without both a pickup and a dropoff pin, send them
    // back to choose a destination rather than firing a request that 400s.
    if (widget.pickupLat == null || widget.pickupLng == null || widget.dropoffLat == null || widget.dropoffLng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Set your pickup and destination on the map first.')),
      );
      return;
    }
    setState(() => _requesting = true);
    try {
      final trip = await BookingApi.requestTrip(
        pickup: _pickup,
        destination: _destination,
        pickupLat: widget.pickupLat!,
        pickupLng: widget.pickupLng!,
        dropoffLat: widget.dropoffLat!,
        dropoffLng: widget.dropoffLng!,
      );
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(builder: (context) => SearchDriverScreen(trip: trip)),
      );
    } catch (e) {
      if (!mounted) return;
      final msg = e is ApiException && e.statusCode == 403
          ? 'Your account isn\'t set up as a rider yet.'
          : e.toString();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      if (mounted) setState(() => _requesting = false);
    }
  }

  Future<void> _loadMarkers() async {
    final markers = await _generateCarMarkers();
    if (mounted) setState(() => _markers = markers);
  }

  Future<Set<Marker>> _generateCarMarkers() async {
    final icon = await BitmapDescriptor.fromAssetImage(
      ImageConfiguration.empty,
      'assets/car_marker.png',
    );
    return List.generate(
      10,
      (i) => Marker(
        markerId: MarkerId('car_$i'),
        position: LatLng(6.524 + i * 0.001, 3.379 + i * 0.001),
        icon: icon,
      ),
    ).toSet();
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
            markers: _markers,
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: _buildSearchBar(),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: _buildTripInfoSheet(context),
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
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
            onPressed: () => Navigator.pop(context),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(_destination, style: const TextStyle(fontSize: 16))),
        ],
      ),
    );
  }

  Widget _buildTripInfoSheet(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [BoxShadow(color: AppColors.border, blurRadius: 10)],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildTripDetail(),
          const SizedBox(height: 16),
          _buildPaymentRow(),
          const SizedBox(height: 20),
          _buildFindDriverButton(),
        ],
      ),
    );
  }

  Widget _buildTripDetail() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Your Trip", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        const SizedBox(height: 8),
        Row(
          children: [
            Image.asset('assets/ic_pickup.png', width: 24, height: 24),
            const SizedBox(width: 8),
            Expanded(child: Text(_pickup, style: const TextStyle(fontSize: 16))),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Image.asset('assets/ic_destination.png', width: 24, height: 24),
            const SizedBox(width: 8),
            Expanded(child: Text(_destination, style: const TextStyle(fontSize: 16))),
          ],
        ),
        const SizedBox(height: 15),
        _buildFareLine(),
      ],
    );
  }

  Widget _buildFareLine() {
    if (_quoteLoading) {
      return Row(
        children: const [
          SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          SizedBox(width: 8),
          Text('Getting fare estimate…', style: TextStyle(fontSize: 14)),
        ],
      );
    }
    if (_quoteError != null) {
      return Text(_quoteError!, style: const TextStyle(color: AppColors.error, fontSize: 13));
    }
    final q = _quote!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Estimated fare: ${Currency.format(q.estimatedFare)}',
            style: const TextStyle(color: AppColors.primaryDark, fontWeight: FontWeight.bold, fontSize: 16)),
        if (q.surgeMultiplier > 1)
          Text('Surge ${q.surgeMultiplier.toStringAsFixed(1)}x in effect',
              style: const TextStyle(color: AppColors.error, fontSize: 12)),
      ],
    );
  }

  Widget _buildPaymentRow() {
    return Row(
      children: [
        const Icon(Icons.credit_card, size: 20),
        const SizedBox(width: 8),
        Text(widget.paymentMethod),
        const Spacer(),
      ],
    );
  }

  Widget _buildFindDriverButton() {
    final canRequest = !_requesting && !_quoteLoading && _quoteError == null;
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: canRequest ? _findDriver : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.textPrimary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        child: _requesting
            ? const SizedBox(
                height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.textPrimary))
            : const Text("Find a driver", style: TextStyle(fontSize: 16)),
      ),
    );
  }
}
