import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:ravelgo_driver_app/models/ride_request.dart';
import 'package:ravelgo_driver_app/services/api_client.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';
import 'package:ravelgo_driver_app/views/safety/emergency_screen.dart';
import 'package:ravelgo_driver_app/views/trip/trip_complete_screen.dart';

enum _TripStage { toPickup, arrivedPickup, inProgress, arrivedDestination }

class ActiveTripScreen extends StatefulWidget {
  final RideRequest request;
  final String? tripId;
  const ActiveTripScreen({super.key, required this.request, this.tripId});

  @override
  State<ActiveTripScreen> createState() => _ActiveTripScreenState();
}

class _ActiveTripScreenState extends State<ActiveTripScreen> {
  _TripStage _stage = _TripStage.toPickup;
  bool _isLoading = false;
  DateTime? _tripStartedAt;

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

  // "Arrived at pickup" and "Arrived at destination" are pure UI stages —
  // the backend's trip status machine (VALID_TRIP_TRANSITIONS in
  // trips.routes.ts) only knows MATCHED, IN_PROGRESS, COMPLETED, CANCELLED,
  // DISPUTED, so only the two transitions that cross one of those
  // boundaries (arrivedPickup -> inProgress, arrivedDestination -> complete)
  // call the API; the others just advance local state.
  Future<void> _advance() async {
    if (_stage == _TripStage.arrivedDestination) {
      await _completeTrip();
      return;
    }

    final nextStage = _TripStage.values[_stage.index + 1];

    if (nextStage == _TripStage.inProgress && widget.tripId != null) {
      setState(() => _isLoading = true);
      try {
        await ApiClient().patch('/trips/${widget.tripId}/status', body: {'status': 'IN_PROGRESS'});
      } catch (e) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to update trip status. Please try again.')),
        );
        return;
      }
      _tripStartedAt = DateTime.now();
    }

    if (!mounted) return;
    setState(() {
      _stage = nextStage;
      _isLoading = false;
    });
  }

  Future<void> _completeTrip() async {
    if (widget.tripId != null) {
      setState(() => _isLoading = true);
      // durationMinutes is the actual elapsed time since IN_PROGRESS, not
      // the pre-trip ETA estimate — calculateFinalFare (backend/services/
      // fare.ts) requires a positive number, so a trip that completes in
      // under a minute (e.g. testing) still reports 1.
      final elapsedMinutes = _tripStartedAt == null
          ? 1
          : DateTime.now().difference(_tripStartedAt!).inMinutes.clamp(1, 999999);
      try {
        await ApiClient().patch('/trips/${widget.tripId}/status', body: {
          'status': 'COMPLETED',
          'distanceKm': widget.request.distanceKm,
          'durationMinutes': elapsedMinutes,
        });
        // Creates the Payment row (and, for CARD, the Stripe PaymentIntent)
        // the rider's payment screen needs — without this call a completed
        // trip has no charge to pay and GET /trips/:id/payment-secret 404s
        // forever. Best-effort: a failure here shouldn't strand the driver
        // mid-completion, since the trip itself already transitioned.
        try {
          await ApiClient().post('/trips/${widget.tripId}/charge', body: {'method': 'CARD'});
        } catch (_) {
          // Non-fatal — an Admin can charge the trip manually if this fails.
        }
      } catch (e) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to complete trip. Please try again.')),
        );
        return;
      }
    }

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => TripCompleteScreen(request: widget.request, tripId: widget.tripId)),
    );
  }

  Future<void> _cancelTrip() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Cancel trip?"),
        content: const Text("Are you sure you want to cancel this trip? Frequent cancellations may affect your rating."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("No, keep trip")),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Yes, cancel", style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    if (widget.tripId != null) {
      setState(() => _isLoading = true);
      try {
        await ApiClient().patch('/trips/${widget.tripId}/status', body: {'status': 'CANCELLED'});
      } catch (e) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to cancel trip. Please try again.')),
        );
        return;
      }
    }

    if (!mounted) return;
    Navigator.of(context).pop();
  }

  void _message() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('In-app messaging coming soon')),
    );
  }

  void _call() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Voice calling coming soon')),
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
                const SizedBox(
                  width: double.infinity,
                  height: 280,
                  child: GoogleMap(
                    initialCameraPosition: CameraPosition(
                      target: LatLng(6.5244, 3.3792),
                      zoom: 14.0,
                    ),
                    myLocationEnabled: true,
                    myLocationButtonEnabled: false,
                    compassEnabled: false,
                    zoomControlsEnabled: false,
                  ),
                ),
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
                Positioned(
                  top: 12,
                  right: 12,
                  child: CircleAvatar(
                    backgroundColor: Colors.white,
                    child: IconButton(
                      icon: const Icon(Icons.close, color: Colors.red),
                      onPressed: _isLoading ? null : _cancelTrip,
                    ),
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
                    if (_isLoading)
                      const Center(child: CircularProgressIndicator())
                    else
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
