import 'package:flutter/material.dart';
import 'package:ravelgo_driver_app/models/driver_operational_state.dart';
import 'package:ravelgo_driver_app/services/api/api_client.dart';
import 'package:ravelgo_driver_app/services/driver_session.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';
import 'package:ravelgo_driver_app/views/safety/emergency_screen.dart';
import 'package:ravelgo_driver_app/views/trip/trip_complete_screen.dart';
import 'package:ravelgo_driver_app/widgets/live_map_preview.dart';

/// Drives the driver's side of a real Trip through the backend's own
/// status transitions (MATCHED -> IN_PROGRESS -> COMPLETED, each a real
/// PATCH /api/trips/:id/status call) — not a local 4-stage simulation.
/// There is no "arrived at pickup"/"arrived at destination" status in the
/// Trip schema, so this screen only shows the two states the backend
/// actually has.
class ActiveTripScreen extends StatefulWidget {
  final Map<String, dynamic> trip;
  const ActiveTripScreen({super.key, required this.trip});

  @override
  State<ActiveTripScreen> createState() => _ActiveTripScreenState();
}

class _ActiveTripScreenState extends State<ActiveTripScreen> {
  late Map<String, dynamic> _trip = widget.trip;
  bool _submitting = false;

  String get _tripId => _trip['id'] as String;
  bool get _inProgress => _trip['status'] == 'IN_PROGRESS';

  @override
  void initState() {
    super.initState();
    // The operational-exclusivity invariant (Part 2: a driver can't be on a
    // ride and also accept a courier request) is enforced here exactly as
    // it is for the real courier flow — DriverSession.instance is the same
    // one both flows read and write. DriverSession.acceptPendingRide()
    // already called markBusy() before this screen was pushed, so this is
    // a defensive re-assertion, not the primary call site.
    if (DriverSession.instance.state != DriverOperationalState.onRide) {
      DriverSession.instance.markBusy(DriverOperationalState.onRide, _tripId);
    }
  }

  @override
  void dispose() {
    // Covers every exit path except the real "trip completed" one (handled
    // explicitly in _complete, since that path also needs to navigate to
    // TripCompleteScreen with the final trip data) — back button or app
    // navigation elsewhere still correctly frees the driver.
    if (_trip['status'] != 'COMPLETED') {
      DriverSession.instance.reconcile(busy: false);
    }
    super.dispose();
  }

  Future<void> _startTrip() async {
    setState(() => _submitting = true);
    try {
      final updated = await DriverSession.instance.rideApi.updateStatus(_tripId, 'IN_PROGRESS');
      if (!mounted) return;
      setState(() {
        _trip = updated;
        _submitting = false;
      });
    } on ApiException catch (err) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err.message)));
    }
  }

  Future<void> _complete() async {
    setState(() => _submitting = true);
    try {
      // Defaults to the trip's own server-established estimatedFare — the
      // backend bounds any driver-submitted finalFare to a ratio of that
      // estimate anyway (FINAL_FARE_MIN/MAX_RATIO), and there is no real
      // fare-adjustment UI here to submit anything else.
      final estimatedFare = (_trip['estimatedFare'] as num).toDouble();
      final updated = await DriverSession.instance.rideApi.updateStatus(_tripId, 'COMPLETED', finalFare: estimatedFare);
      DriverSession.instance.reconcile(busy: false);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => TripCompleteScreen(trip: updated)));
    } on ApiException catch (err) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err.message)));
    }
  }

  void _message() {
    const presets = [
      "I'm on my way",
      "I've arrived, look out for a yellow-plate vehicle",
      "Running 2 minutes late",
      "Please come down, I'm outside",
    ];
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(padding: EdgeInsets.all(16), child: Text("Message rider", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
            ...presets.map((m) => ListTile(title: Text(m), onTap: () => Navigator.pop(context))),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const TextField(decoration: InputDecoration(hintText: "Write your own message")),
            ),
          ],
        ),
      ),
    );
  }

  void _call() {
    final rider = _trip['rider'] as Map<String, dynamic>?;
    final riderName = rider != null ? '${rider['firstName']} ${rider['lastName']}' : 'the rider';
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Calling rider"),
        content: Text("Connecting an in-app voice call with $riderName. Your phone number stays private."),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("End call"))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rider = _trip['rider'] as Map<String, dynamic>?;
    final riderName = rider != null ? '${rider['firstName']} ${rider['lastName']}' : 'Rider';
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            Stack(
              children: [
                const LiveMapPreview(height: 280),
                Positioned(
                  top: 12,
                  left: 12,
                  child: CircleAvatar(
                    backgroundColor: Colors.white,
                    child: IconButton(icon: const Icon(Icons.shield_outlined, color: Colors.red), onPressed: () {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const EmergencyScreen()));
                    }),
                  ),
                ),
              ],
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppComponents.badge(_inProgress ? "Trip in progress" : "Heading to pickup"),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const CircleAvatar(radius: 22, backgroundColor: Color(0xFFF0F0F0), child: Icon(Icons.person, color: Colors.black45)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(riderName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                              Text(
                                _inProgress ? (_trip['destination'] as String? ?? '') : (_trip['pickup'] as String? ?? ''),
                                style: const TextStyle(fontSize: 12.5, color: Colors.black54),
                              ),
                            ],
                          ),
                        ),
                        IconButton(onPressed: _call, icon: const Icon(Icons.call_outlined)),
                        IconButton(onPressed: _message, icon: const Icon(Icons.message_outlined)),
                      ],
                    ),
                    const SizedBox(height: 20),
                    const Spacer(),
                    AppComponents.primaryButton(
                      text: _submitting ? "Updating..." : (_inProgress ? "Complete trip" : "Start trip"),
                      onPressed: _submitting ? null : (_inProgress ? _complete : _startTrip),
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
}
