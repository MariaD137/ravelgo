import 'package:flutter/material.dart';
import 'package:ravelgo_driver_app/services/api_client.dart';
import 'package:ravelgo_driver_app/services/driver_api.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';
import 'package:ravelgo_driver_app/views/safety/emergency_screen.dart';
import 'package:ravelgo_driver_app/views/trip/trip_complete_screen.dart';

/// Drives a REAL matched trip through its lifecycle (P0 #3). The two stage
/// changes that matter to the backend — starting the trip and completing it —
/// call PATCH /api/trips/:id/status, which enforces the driver's allowed
/// transitions (MATCHED→IN_PROGRESS, IN_PROGRESS→COMPLETED). The "arrived"
/// stages in between are local driver progress only. The trip arrives here
/// still MATCHED (the driver accepted); it is not marked underway until the
/// driver actually starts it.
enum _TripStage { toPickup, arrivedPickup, inProgress, arrivedDestination }

class ActiveTripScreen extends StatefulWidget {
  final DriverTrip trip;
  const ActiveTripScreen({super.key, required this.trip});

  @override
  State<ActiveTripScreen> createState() => _ActiveTripScreenState();
}

class _ActiveTripScreenState extends State<ActiveTripScreen> {
  _TripStage _stage = _TripStage.toPickup;
  bool _busy = false;
  late DriverTrip _trip = widget.trip;

  String get _stageLabel {
    switch (_stage) {
      case _TripStage.toPickup:
        return "Heading to pickup";
      case _TripStage.arrivedPickup:
        return "Arrived at pickup";
      case _TripStage.inProgress:
        return "Trip in progress";
      case _TripStage.arrivedDestination:
        return "Arrived at destination";
    }
  }

  String get _actionLabel {
    switch (_stage) {
      case _TripStage.toPickup:
        return "Arrived at pickup";
      case _TripStage.arrivedPickup:
        return "Start trip";
      case _TripStage.inProgress:
        return "Arrived at destination";
      case _TripStage.arrivedDestination:
        return "Complete trip";
    }
  }

  Future<void> _advance() async {
    // "Start trip" and "Complete trip" are the two real backend transitions;
    // the "arrived" stages are local progress only.
    if (_stage == _TripStage.arrivedPickup) {
      await _transition('IN_PROGRESS', then: () {
        setState(() => _stage = _TripStage.inProgress);
      });
      return;
    }
    if (_stage == _TripStage.arrivedDestination) {
      await _transition('COMPLETED', then: () {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => TripCompleteScreen(trip: _trip)),
        );
      });
      return;
    }
    setState(() => _stage = _TripStage.values[_stage.index + 1]);
  }

  Future<void> _transition(String status, {required VoidCallback then}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final updated = await DriverApi.updateTripStatus(_trip.id, status);
      if (!mounted) return;
      setState(() => _trip = updated);
      then();
    } catch (e) {
      if (!mounted) return;
      final msg = e is ApiException ? e.message : e.toString();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      if (mounted) setState(() => _busy = false);
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
            const Padding(
                padding: EdgeInsets.all(16),
                child: Text("Message rider", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
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
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Calling rider"),
        content: Text("Connecting an in-app voice call with ${_trip.riderName ?? 'the rider'}. Your phone number stays private."),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("End call"))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Stack(
              children: [
                Image.asset('assets/fake_map.png', width: double.infinity, height: 280, fit: BoxFit.cover),
                Positioned(
                  top: 12,
                  left: 12,
                  child: CircleAvatar(
                    backgroundColor: AppColors.surfaceElevated,
                    child: IconButton(
                        icon: const Icon(Icons.shield_outlined, color: AppColors.error),
                        onPressed: () {
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
                    AppComponents.badge(_stageLabel),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const CircleAvatar(
                            radius: 22,
                            backgroundColor: AppColors.surfaceElevated,
                            child: Icon(Icons.person, color: AppColors.textSecondary)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_trip.riderName ?? 'Rider',
                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                              Text(_stage.index < 2 ? _trip.pickup : _trip.destination,
                                  style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                            ],
                          ),
                        ),
                        IconButton(onPressed: _call, icon: const Icon(Icons.call_outlined)),
                        IconButton(onPressed: _message, icon: const Icon(Icons.message_outlined)),
                      ],
                    ),
                    const SizedBox(height: 20),
                    const Spacer(),
                    AppComponents.primaryButton(text: _actionLabel, onPressed: _busy ? null : _advance),
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
