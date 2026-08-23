import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:ravelgo_rider_app/services/ride_session.dart';
import 'package:ravelgo_rider_app/views/TexiModule/CancelRideScreen.dart';

/// Shown right after POST /trips is sent, while the trip is still
/// REQUESTED. Backend matching (services/matching.ts) runs synchronously
/// inside that same request/response, or leaves the trip unmatched for
/// [RideSession]'s poll loop to pick up once a driver frees up — either
/// way, the instant [RideSession.currentTrip] reports a status other than
/// REQUESTED, this screen hands off to Home's persistent ride sheet
/// (ride_view_popup.dart), which is what actually drives the rest of the
/// trip (driver info, live status, cancel while still cancellable).
class SearchDriverScreen extends StatefulWidget {
  const SearchDriverScreen({super.key});

  @override
  State<SearchDriverScreen> createState() => _SearchDriverScreenState();
}

class _SearchDriverScreenState extends State<SearchDriverScreen> {
  final RideSession _session = RideSession.instance;
  bool _cancelling = false;

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
    if (!mounted) return;
    final status = _session.currentTrip?['status'] as String?;
    if (status != null && status != 'REQUESTED') {
      // Matched (or already moved past that) — hand off to Home's
      // persistent ride sheet, which now shows the real driver/status.
      Navigator.of(context).popUntil((route) => route.isFirst);
      return;
    }
    setState(() {});
  }

  Future<void> _cancel() async {
    setState(() => _cancelling = true);
    final ok = await _session.cancelTrip();
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    } else {
      setState(() => _cancelling = false);
      if (_session.requestError != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_session.requestError!)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: const CameraPosition(target: LatLng(6.5244, 3.3792), zoom: 14),
            myLocationEnabled: true,
            zoomControlsEnabled: false,
          ),
          SafeArea(
            child: Padding(padding: const EdgeInsets.all(16), child: _buildSearchBar()),
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
                      child: ListView(controller: scrollController, children: [_buildBottomSheet()]),
                    ),
                    _buildCancelButton(),
                    const SizedBox(height: 12),
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
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8)],
      ),
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

  Widget _buildBottomSheet() {
    final fare = (_session.currentTrip?['estimatedFare'] as num?)?.toStringAsFixed(0) ??
        (_session.quote?['estimatedFare'] as num?)?.toStringAsFixed(0);
    return Container(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(35),
            decoration: const BoxDecoration(color: Color(0xFFFFF3CD), shape: BoxShape.circle),
            child: Column(
              children: [
                const Text("Finding a driver...", style: TextStyle(fontWeight: FontWeight.w500, fontSize: 14)),
                const SizedBox(height: 12),
                const CircularProgressIndicator(),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _buildTripInfo(fare),
        ],
      ),
    );
  }

  Widget _buildTripInfo(String? fare) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Your Trip", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        const SizedBox(height: 8),
        Row(
          children: [
            const Icon(Icons.radio_button_checked, color: Colors.green, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(_session.pickup ?? '—', overflow: TextOverflow.ellipsis)),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Icon(Icons.place, color: Colors.redAccent, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(_session.destination ?? '—', overflow: TextOverflow.ellipsis)),
          ],
        ),
        const SizedBox(height: 15),
        Text(fare != null ? "Fare: ₦$fare" : "Fare unavailable", style: const TextStyle(fontWeight: FontWeight.w500)),
      ],
    );
  }

  Widget _buildCancelButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: _cancelling
              ? null
              : () {
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (context) {
                      return FractionallySizedBox(
                        heightFactor: 0.8,
                        child: ClipRRect(
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                          child: CancelRideScreen(onConfirm: _cancel),
                        ),
                      );
                    },
                  );
                },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.yellow[700],
            foregroundColor: Colors.black,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          child: _cancelling
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text("Cancel request"),
        ),
      ),
    );
  }
}
