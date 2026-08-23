import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:ravelgo_rider_app/services/ride_session.dart';
import 'package:ravelgo_rider_app/views/TexiModule/SearchDriverScreen.dart';

class FindDriverScreen extends StatefulWidget {
  const FindDriverScreen({super.key});

  @override
  State<FindDriverScreen> createState() => _FindDriverScreenState();
}

class _FindDriverScreenState extends State<FindDriverScreen> {
  final RideSession _session = RideSession.instance;

  @override
  void initState() {
    super.initState();
    _session.addListener(_onSessionChanged);
  }

  @override
  void dispose() {
    _session.removeListener(_onSessionChanged);
    super.dispose();
  }

  void _onSessionChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _requestRide() async {
    // RideSession.requestTrip is itself guarded against a second concurrent
    // call, but bail out here too so the button doesn't even attempt a
    // second tap while the first request is still in flight.
    if (_session.requesting) return;
    final ok = await _session.requestTrip();
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).push(MaterialPageRoute(builder: (context) => const SearchDriverScreen()));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_session.requestError ?? 'Could not request a ride. Try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          GoogleMap(
            onMapCreated: (controller) {},
            initialCameraPosition: const CameraPosition(target: LatLng(6.5244, 3.3792), zoom: 14),
            myLocationEnabled: true,
            zoomControlsEnabled: false,
          ),

          SafeArea(
            child: Padding(padding: const EdgeInsets.all(16), child: _buildSearchBar()),
          ),

          Align(alignment: Alignment.bottomCenter, child: _buildTripInfoSheet(context)),
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

  Widget _buildTripInfoSheet(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10)],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildTripDetail(),
          const SizedBox(height: 20),
          _buildFindDriverButton(),
        ],
      ),
    );
  }

  Widget _buildTripDetail() {
    final fare = (_session.quote?['estimatedFare'] as num?)?.toStringAsFixed(0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Your Trip", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        const SizedBox(height: 8),
        Row(
          children: [
            const Icon(Icons.radio_button_checked, color: Colors.green, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _session.pickup ?? 'Pickup',
                style: const TextStyle(fontSize: 16),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Icon(Icons.place, color: Colors.redAccent, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _session.destination ?? 'Destination',
                style: const TextStyle(fontSize: 16),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 15),
        Text(
          fare != null ? "Fare: ₦$fare" : "Fare unavailable",
          style: const TextStyle(color: Colors.brown, fontWeight: FontWeight.bold, fontSize: 14),
        ),
      ],
    );
  }

  Widget _buildFindDriverButton() {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton(
            onPressed: _session.requesting || _session.quote == null ? null : _requestRide,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amber,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: _session.requesting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                  )
                : const Text("Find a driver", style: TextStyle(fontSize: 16)),
          ),
        ),
      ],
    );
  }
}
