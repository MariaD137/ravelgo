import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:ravelgo_rider_app/services/ride_session.dart';
import 'package:ravelgo_rider_app/views/TexiModule/FindDriverScreen.dart';

class SelectRide extends StatefulWidget {
  const SelectRide({super.key});

  @override
  State<SelectRide> createState() => _SelectRideState();
}

class _SelectRideState extends State<SelectRide> {
  GoogleMapController? mapController;

  final LatLng _center = const LatLng(6.6018, 3.3515); // Sample: Lagos

  final RideSession _session = RideSession.instance;

  @override
  void initState() {
    super.initState();
    _session.addListener(_onSessionChanged);
    if (_session.quote == null && !_session.quoteLoading) {
      _session.fetchQuote();
    }
  }

  @override
  void dispose() {
    _session.removeListener(_onSessionChanged);
    super.dispose();
  }

  void _onSessionChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          GoogleMap(
            onMapCreated: (controller) => mapController = controller,
            initialCameraPosition: CameraPosition(target: _center, zoom: 14.0),
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
          ),

          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: _buildSearchBar(),
            ),
          ),

          Positioned(
            right: 16,
            bottom: 280,
            child: CircleAvatar(
              backgroundColor: Colors.white,
              child: IconButton(icon: const Icon(Icons.my_location), onPressed: () {}),
            ),
          ),

          DraggableScrollableSheet(
            initialChildSize: 0.4,
            minChildSize: 0.35,
            maxChildSize: 0.65,
            builder: (_, controller) {
              return Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                padding: const EdgeInsets.only(left: 12, top: 12, right: 12),
                child: Column(
                  children: [
                    const Text("Choose a ride", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    Expanded(child: ListView(controller: controller, children: [_buildFareCard()])),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.black,
                            elevation: 0,
                            side: const BorderSide(color: Colors.black12),
                          ),
                          icon: Image.asset("assets/ic_cash_ride.png"),
                          label: const Text("Cash"),
                          onPressed: () {},
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.yellow.shade600,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            onPressed: _session.quote == null
                                ? null
                                : () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(builder: (context) => const FindDriverScreen()),
                                    );
                                  },
                            child: const Text("Select ride", style: TextStyle(color: Colors.black)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildFareCard() {
    if (_session.quoteLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_session.quoteError != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          children: [
            Text(_session.quoteError!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 8),
            TextButton(onPressed: () => _session.fetchQuote(), child: const Text("Retry")),
          ],
        ),
      );
    }
    final quote = _session.quote;
    if (quote == null) return const SizedBox.shrink();
    final fare = (quote['estimatedFare'] as num).toStringAsFixed(0);
    final distanceKm = _session.distanceKm?.toStringAsFixed(1) ?? '—';
    final etaMinutes = _session.durationMinutes?.round() ?? 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 12, left: 5, right: 5),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.green, width: 1.5),
        borderRadius: BorderRadius.circular(12),
        color: Colors.white,
      ),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          const Icon(Icons.directions_car),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Ride", style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text("$etaMinutes min · ${distanceKm}km"),
              ],
            ),
          ),
          Text("₦$fare", style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(30)),
      child: Row(
        children: [
          IconButton(icon: const Icon(Icons.arrow_back, color: Colors.black), onPressed: () => Navigator.pop(context)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _session.destination ?? 'Where to?',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}
