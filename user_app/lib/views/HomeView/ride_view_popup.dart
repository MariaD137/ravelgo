import 'package:flutter/material.dart';
import 'package:ravelgo_rider_app/services/ride_session.dart';

/// Live status of the rider's current trip, driven entirely by
/// [RideSession] — its polling loop and best-effort WebSocket connection
/// (see ride_session.dart) are what actually advance this UI, never a
/// local timer simulating progress. [widget.onClose] is only called once
/// the backend has reported a terminal trip status (COMPLETED, CANCELLED,
/// or DISPUTED), or the rider cancels and that cancellation is confirmed
/// by the server.
class RideViewPopup extends StatefulWidget {
  final VoidCallback onClose;

  const RideViewPopup({Key? key, required this.onClose}) : super(key: key);

  @override
  State<RideViewPopup> createState() => _RideViewPopupState();
}

class _RideViewPopupState extends State<RideViewPopup> {
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
    if (mounted) setState(() {});
  }

  Future<void> _cancel() async {
    setState(() => _cancelling = true);
    final ok = await _session.cancelTrip();
    if (!mounted) return;
    setState(() => _cancelling = false);
    if (!ok && _session.requestError != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_session.requestError!)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final trip = _session.currentTrip;
    final status = trip?['status'] as String?;
    final isTerminal = status == 'COMPLETED' || status == 'CANCELLED' || status == 'DISPUTED';

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFF6F6F6),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          Expanded(
            child: isTerminal
                ? _terminalView(trip, status)
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(0),
                    child: Column(
                      children: [
                        _topBar(),
                        _statusTitle(status),
                        const SizedBox(height: 16),
                        _driverSection(trip),
                        const SizedBox(height: 16),
                        _routeCard(trip),
                        if (status == 'MATCHED' || status == 'REQUESTED') ...[
                          const SizedBox(height: 16),
                          _cancelButton(),
                        ],
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _topBar() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(top: 12, bottom: 18),
      decoration: const BoxDecoration(
        color: Color(0xFFFFD500),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          Container(
            width: 48,
            height: 5,
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(color: Colors.white70, borderRadius: BorderRadius.circular(10)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.shield_outlined, size: 16),
                SizedBox(width: 6),
                Text("Safety", style: TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusTitle(String? status) {
    final text = switch (status) {
      'REQUESTED' => 'Finding a driver...',
      'MATCHED' => 'Your driver is on the way',
      'IN_PROGRESS' => 'Driving to your destination',
      _ => 'Trip status unavailable',
    };
    return Text(
      text,
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF9C7B00)),
    );
  }

  Widget _driverSection(Map<String, dynamic>? trip) {
    final driver = trip?['driver'] as Map<String, dynamic>?;
    final driverUser = driver?['user'] as Map<String, dynamic>?;
    final name = driverUser != null ? '${driverUser['firstName']} ${driverUser['lastName']}' : null;
    final rating = (driver?['rating'] as num?)?.toStringAsFixed(2);
    final phone = driverUser?['phoneNumber'] as String?;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          Row(
            children: [
              const CircleAvatar(radius: 22, child: Icon(Icons.person)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name ?? 'Waiting for a driver to be assigned...',
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                    ),
                    if (rating != null) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.star, size: 16, color: Colors.green),
                          const SizedBox(width: 4),
                          Text("$rating Rating", style: const TextStyle(fontSize: 13)),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (phone != null) ...[
            const Divider(height: 28),
            Row(
              children: [
                const Icon(Icons.phone, size: 18),
                const SizedBox(width: 8),
                Text(phone),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _routeCard(Map<String, dynamic>? trip) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("My route", style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Text(trip?['pickup'] as String? ?? '—'),
          const SizedBox(height: 6),
          Text(trip?['destination'] as String? ?? '—'),
        ],
      ),
    );
  }

  Widget _cancelButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton(
          onPressed: _cancelling ? null : _cancel,
          style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.red)),
          child: _cancelling
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text("Cancel ride", style: TextStyle(color: Colors.red)),
        ),
      ),
    );
  }

  Widget _terminalView(Map<String, dynamic>? trip, String? status) {
    final fare = (trip?['finalFare'] as num?) ?? (trip?['estimatedFare'] as num?);
    final title = switch (status) {
      'COMPLETED' => 'Trip completed',
      'CANCELLED' => 'Trip cancelled',
      'DISPUTED' => 'Trip disputed',
      _ => 'Trip ended',
    };
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const SizedBox(),
          Column(
            children: [
              Text(title, style: const TextStyle(color: Color(0xFF9C7B00), fontWeight: FontWeight.w600)),
              if (fare != null) ...[
                const SizedBox(height: 12),
                Text('₦${fare.toStringAsFixed(0)}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              ],
              const SizedBox(height: 4),
              Text(trip?['destination'] as String? ?? ''),
            ],
          ),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4E7D2A)),
              onPressed: () {
                _session.clearTrip();
                widget.onClose();
              },
              child: const Text("DONE"),
            ),
          ),
        ],
      ),
    );
  }
}
