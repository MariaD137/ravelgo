import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:ravelgo_user_app/components/SafeGoogleMap.dart';
import 'package:ravelgo_user_app/config/currency.dart';
import 'RidesView.dart'; // adjust path if needed; this imports the Ride class
import 'package:ravelgo_user_app/services/api_client.dart';
import 'package:ravelgo_user_app/services/trips_api.dart';
import 'package:ravelgo_user_app/theme/app_theme.dart';
import 'package:ravelgo_user_app/views/AccountView/EReceiptPage.dart';

class RideDetailsScreen extends StatefulWidget {
  final Ride ride;

  const RideDetailsScreen({Key? key, required this.ride}) : super(key: key);

  @override
  State<RideDetailsScreen> createState() => _RideDetailsScreenState();
}

class _RideDetailsScreenState extends State<RideDetailsScreen> {
  Ride get ride => widget.ride;

  // The route this trip actually took, fetched from the backend. The list
  // route (GET /api/trips) deliberately stays minimal and carries no
  // coordinates, so the map needs the single-trip route.
  Trip? _trip;
  bool _loadingRoute = true;
  String? _routeError;

  @override
  void initState() {
    super.initState();
    _loadRoute();
  }

  Future<void> _loadRoute() async {
    setState(() {
      _loadingRoute = true;
      _routeError = null;
    });
    try {
      final trip = await TripsApi.byId(ride.tripId);
      if (!mounted) return;
      setState(() {
        _trip = trip;
        _loadingRoute = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _routeError = describeApiFailure(e, what: 'this trip\'s route');
        _loadingRoute = false;
      });
    }
  }

  /// The real pickup/dropoff markers for this trip, or an empty set when the
  /// backend has no coordinates for it (older trips created before
  /// coordinates were required).
  Set<Marker> get _markers {
    final t = _trip;
    if (t == null) return const {};
    return {
      if (t.pickupLat != null && t.pickupLng != null)
        Marker(
          markerId: const MarkerId('pickup'),
          position: LatLng(t.pickupLat!, t.pickupLng!),
          infoWindow: InfoWindow(title: 'Pickup', snippet: t.pickup),
        ),
      if (t.dropoffLat != null && t.dropoffLng != null)
        Marker(
          markerId: const MarkerId('dropoff'),
          position: LatLng(t.dropoffLat!, t.dropoffLng!),
          infoWindow: InfoWindow(title: 'Destination', snippet: t.destination),
        ),
    };
  }

  /// A map of the real route, a plain message when this trip has no
  /// coordinates, or the failure that stopped us loading it. Never a picture
  /// of somebody else's journey: this used to be a static bitmap of an
  /// unrelated map, shown for every trip as though it were this one.
  Widget _routePreview() {
    if (_loadingRoute) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_routeError != null) {
      return _routePlaceholder(
        icon: Icons.error_outline,
        message: _routeError!,
        onRetry: _loadRoute,
      );
    }
    final markers = _markers;
    if (markers.isEmpty) {
      return _routePlaceholder(
        icon: Icons.map_outlined,
        message: 'No route was recorded for this trip.',
      );
    }
    final first = markers.first.position;
    return SafeGoogleMap(
      initialCameraPosition: CameraPosition(target: first, zoom: 13),
      markers: markers,
      myLocationEnabled: false,
      myLocationButtonEnabled: false,
      zoomControlsEnabled: false,
      onMapCreated: (controller) => _fitRoute(controller, markers),
    );
  }

  void _fitRoute(GoogleMapController controller, Set<Marker> markers) {
    if (markers.length < 2) return;
    final positions = markers.map((m) => m.position).toList();
    final bounds = LatLngBounds(
      southwest: LatLng(
        positions.map((p) => p.latitude).reduce((a, b) => a < b ? a : b),
        positions.map((p) => p.longitude).reduce((a, b) => a < b ? a : b),
      ),
      northeast: LatLng(
        positions.map((p) => p.latitude).reduce((a, b) => a > b ? a : b),
        positions.map((p) => p.longitude).reduce((a, b) => a > b ? a : b),
      ),
    );
    controller.animateCamera(CameraUpdate.newLatLngBounds(bounds, 48));
  }

  Widget _routePlaceholder({
    required IconData icon,
    required String message,
    VoidCallback? onRetry,
  }) {
    return Container(
      color: AppColors.background,
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 32, color: AppColors.textMuted),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 10),
            OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final months = [
      '',
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final minute = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'pm' : 'am';
    return '${dt.day} ${months[dt.month]}. $hour:$minute $ampm';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Column(
          children: [
            // Top bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8),
              child: Row(
                children: [
                  IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.of(context).pop()),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            ride.driverName != null && ride.driverName!.isNotEmpty
                                ? 'Ride with ${ride.driverName}'
                                : 'Trip to ${ride.destination.isNotEmpty ? ride.destination : ride.title}',
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        Text(_formatTime(ride.dateTime), style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Map preview — this trip's real pickup and destination.
            SizedBox(height: 300, child: _routePreview()),

            // Details & payments
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Real pickup -> destination for this trip.
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // timeline indicator
                        Column(
                          children: [
                            Container(width: 18, height: 18, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.green)),
                            Container(width: 2, height: 48, color: AppColors.border),
                            Container(width: 18, height: 18, decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.textMuted)),
                          ],
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(ride.pickup.isNotEmpty ? ride.pickup : 'Pickup',
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                              const SizedBox(height: 48),
                              Text(ride.destination.isNotEmpty ? ride.destination : 'Destination',
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 18),
                    const Text('Payments', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 12),

                    _paymentRow('Ride Fare', Currency.format(ride.fare)),
                    const Divider(height: 22, color: AppColors.textMuted),

                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6.0),
                      child: Row(
                        children: [
                          const Expanded(child: Text('Total', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
                          Text(Currency.format(ride.fare), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => EReceiptPage(ride: ride)),
                      ),
                      icon: const Icon(Icons.receipt_long_outlined),
                      label: const Text('View E-Receipt'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _paymentRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        children: [
          Expanded(child: Text(label, style: TextStyle(color: AppColors.textSecondary))),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}