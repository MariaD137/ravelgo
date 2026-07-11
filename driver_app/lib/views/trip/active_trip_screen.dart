import 'package:flutter/material.dart';
import 'package:ravelgo_driver_app/models/ride_request.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';
import 'package:ravelgo_driver_app/views/safety/emergency_screen.dart';
import 'package:ravelgo_driver_app/views/trip/trip_complete_screen.dart';

enum _TripStage { toPickup, arrivedPickup, inProgress, arrivedDestination }

class ActiveTripScreen extends StatefulWidget {
  final RideRequest request;
  const ActiveTripScreen({super.key, required this.request});

  @override
  State<ActiveTripScreen> createState() => _ActiveTripScreenState();
}

class _ActiveTripScreenState extends State<ActiveTripScreen> {
  _TripStage _stage = _TripStage.toPickup;

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

  void _advance() {
    if (_stage == _TripStage.arrivedDestination) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => TripCompleteScreen(request: widget.request)),
      );
      return;
    }
    setState(() {
      _stage = _TripStage.values[_stage.index + 1];
    });
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
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Calling rider"),
        content: Text("Connecting an in-app voice call with ${widget.request.riderName}. Your phone number stays private."),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("End call"))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.request;
    return Scaffold(
      backgroundColor: Colors.white,
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
                    AppComponents.badge(_stageLabel),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const CircleAvatar(radius: 22, backgroundColor: Color(0xFFF0F0F0), child: Icon(Icons.person, color: Colors.black45)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(r.riderName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                              Text(_stage.index < 2 ? r.pickup : r.destination, style: const TextStyle(fontSize: 12.5, color: Colors.black54)),
                            ],
                          ),
                        ),
                        IconButton(onPressed: _call, icon: const Icon(Icons.call_outlined)),
                        IconButton(onPressed: _message, icon: const Icon(Icons.message_outlined)),
                      ],
                    ),
                    const SizedBox(height: 20),
                    const Spacer(),
                    AppComponents.primaryButton(text: _actionLabel, onPressed: _advance),
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
