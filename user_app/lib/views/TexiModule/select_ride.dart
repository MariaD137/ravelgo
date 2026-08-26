import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:ravelgo_user/services/api_client.dart';
import 'package:ravelgo_user/services/trip_service.dart';
import 'package:ravelgo_user/views/TexiModule/search_driver_screen.dart';

class _RideTier {
  final String name;
  final double fare;
  final String eta;
  final String seats;
  const _RideTier(this.name, this.fare, this.eta, this.seats);
}

const _tiers = [
  _RideTier('Just ride', 8000, '2min', '4'),
  _RideTier('EV', 6000, '2min', '4'),
  _RideTier('Lite', 5000, '4min', '3'),
];

class SelectRide extends StatefulWidget {
  final String pickup;
  final String destination;

  const SelectRide({super.key, required this.pickup, required this.destination});

  @override
  State<SelectRide> createState() => _SelectRideState();
}

class _SelectRideState extends State<SelectRide> {
  GoogleMapController? mapController;
  final LatLng _center = const LatLng(6.6018, 3.3515); // Sample: Lagos

  int _selectedTier = 0;
  bool _submitting = false;
  String? _error;

  Future<void> _requestRide() async {
    setState(() {
      _submitting = true;
      _error = null;
    });

    final tier = _tiers[_selectedTier];
    try {
      final created = await TripService().requestTrip(
        pickup: widget.pickup,
        destination: widget.destination,
        estimatedFare: tier.fare,
        category: tier.name,
      );
      // The create response never includes the driver relation (see
      // backend/src/routes/trips.routes.ts) — fetch the full trip so a
      // synchronous match already shows real driver info immediately.
      final tripId = created['id'] as String;
      final trip = await TripService().getTrip(tripId);

      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(builder: (context) => SearchDriverScreen(trip: trip)),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Unable to request a ride. Please try again.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Google Map
          GoogleMap(
            onMapCreated: (controller) => mapController = controller,
            initialCameraPosition: CameraPosition(
              target: _center,
              zoom: 14.0,
            ),
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
          ),

          // Top bar with back, location search, and add
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: _buildSearchBar(),
            ),
          ),

          // Location button
          Positioned(
            right: 16,
            bottom: 280,
            child: CircleAvatar(
              backgroundColor: Colors.white,
              child: IconButton(
                icon: const Icon(Icons.my_location),
                onPressed: () {},
              ),
            ),
          ),

          // Bottom draggable sheet
          DraggableScrollableSheet(
            initialChildSize: 0.4,
            minChildSize: 0.4,
            maxChildSize: 0.7,
            builder: (_, controller) {
              return Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                padding: const EdgeInsets.only(left: 12, top: 12, right: 12),
                child: Column(
                  children: [
                    const Text(
                      "Choose a ride",
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    Expanded(
                      child: ListView(
                        controller: controller,
                        children: [
                          for (var i = 0; i < _tiers.length; i++)
                            rideCard(i, isSelected: i == _selectedTier),
                        ],
                      ),
                    ),
                    if (_error != null) ...[
                      Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
                      const SizedBox(height: 8),
                    ],
                    const SizedBox(height: 4),

                    // Payment and Delivery Row
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
                        const SizedBox(width: 8),
                        Expanded(
                          child: Container(
                            height: 48,
                            decoration: BoxDecoration(
                              color: Colors.grey.shade200,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: const Align(
                              alignment: Alignment.centerLeft,
                              child: Text("Pick up a delivery"),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Main CTA
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.yellow.shade600,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            onPressed: _submitting ? null : _requestRide,
                            child: _submitting
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : Text("Select ${_tiers[_selectedTier].name}", style: const TextStyle(color: Colors.black)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.black,
                            shape: const CircleBorder(),
                            padding: const EdgeInsets.all(12),
                          ),
                          onPressed: () {},
                          child: const Icon(Icons.calendar_today, color: Colors.white, size: 20),
                        )
                      ],
                    ),
                    const SizedBox(height: 0),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.black),
            onPressed: () => Navigator.pop(context),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              widget.destination,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget rideCard(int index, {bool isSelected = false}) {
    final tier = _tiers[index];
    return GestureDetector(
      onTap: () => setState(() => _selectedTier = index),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12, left: 5, right: 5),
        decoration: BoxDecoration(
          border: isSelected
              ? Border.all(color: Colors.green, style: BorderStyle.solid, width: 1.5, strokeAlign: BorderSide.strokeAlignOutside)
              : Border.all(color: Colors.grey, style: BorderStyle.solid, width: 1, strokeAlign: BorderSide.strokeAlignOutside),
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
                  Text(tier.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(tier.eta),
                      const SizedBox(width: 8),
                      const Icon(Icons.person, size: 16),
                      Text(tier.seats),
                    ],
                  )
                ],
              ),
            ),
            Text('NGN ${tier.fare.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
