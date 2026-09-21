import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:ravelgo_driver_app/services/api_client.dart';
import 'package:ravelgo_driver_app/services/driver_api.dart';
import 'package:ravelgo_driver_app/services/realtime_service.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';
import 'package:ravelgo_driver_app/views/safety/emergency_screen.dart';
import 'package:ravelgo_driver_app/views/trip/trip_complete_screen.dart';
import 'package:ravelgo_driver_app/widgets/app_page_route.dart';

/// Drives a REAL matched trip through its lifecycle (P0 #3). The two stage
/// changes that matter to the backend — starting the trip and completing it —
/// call PATCH /api/trips/:id/status, which enforces the driver's allowed
/// transitions (MATCHED→IN_PROGRESS, IN_PROGRESS→COMPLETED). The "arrived"
/// stages in between are local driver progress only. The trip arrives here
/// still MATCHED (the driver accepted); it is not marked underway until the
/// driver actually starts it.
///
/// Shows a real map (the driver's own live position via GoogleMap's built-in
/// blue dot, plus a pickup/destination marker from the trip's real
/// Places-resolved coordinates) rather than a static image, and streams the
/// driver's position to the backend the whole time this screen is open —
/// the same RealtimeService/geolocator pipeline trip_detail_screen.dart
/// already uses, so the rider's live tracking and the admin Live Map get a
/// real feed for the entire active trip, not just the IN_PROGRESS half.
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

  final RealtimeService _rt = RealtimeService();
  Timer? _locTimer;
  bool _streaming = false;

  @override
  void initState() {
    super.initState();
    _startStreaming();
  }

  @override
  void dispose() {
    _stopStreaming();
    super.dispose();
  }

  /// The driver's live position matters for the whole time this screen is
  /// open — heading to pickup or already underway — not just once the trip
  /// is formally IN_PROGRESS, so this starts immediately and only stops when
  /// the screen itself closes (the trip finishes or the driver backs out).
  Future<void> _startStreaming() async {
    if (_streaming || !RealtimeService.isConfigured) return;
    final ok = await _rt.connect();
    if (!ok) return;
    _streaming = true;
    _pushLocation();
    _locTimer = Timer.periodic(const Duration(seconds: 5), (_) => _pushLocation());
  }

  void _stopStreaming() {
    _locTimer?.cancel();
    _locTimer = null;
    if (_streaming) _rt.dispose();
    _streaming = false;
  }

  Future<void> _pushLocation() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return;
      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      _rt.sendLocation(pos.latitude, pos.longitude);
    } catch (_) {
      // Best-effort: a failed fix just means no update this tick.
    }
  }

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
        _stopStreaming();
        Navigator.of(context).pushReplacement(
          AppPageRoute(builder: (_) => TripCompleteScreen(trip: _trip)),
        );
      });
      return;
    }
    final nextStage = _TripStage.values[_stage.index + 1];
    setState(() => _stage = nextStage);
    if (nextStage == _TripStage.arrivedPickup) {
      _reportArrived();
    }
  }

  /// Tell the backend the driver has physically reached pickup, so the
  /// server-side waiting-charge clock can start (POST /api/trips/:id/arrived).
  /// Best-effort by design: a failure here just means the free-waiting-period
  /// clock doesn't start for this trip — a minor miss, not worth blocking the
  /// UI or surfacing an error to the driver over.
  Future<void> _reportArrived() async {
    try {
      final updated = await DriverApi.reportArrived(_trip.id);
      if (mounted) setState(() => _trip = updated);
    } catch (_) {
      // Best-effort — see doc comment above.
    }
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

  /// Before arriving at pickup, the destination marker is still the pickup
  /// point; once past it, the destination becomes the drop-off — matching
  /// what _stageLabel already shows in the address row below the map.
  bool get _headingToPickup => _stage == _TripStage.toPickup || _stage == _TripStage.arrivedPickup;

  Set<Marker> get _markers {
    final markers = <Marker>{};
    final r = _trip;
    if (r.pickupLat != null && r.pickupLng != null) {
      markers.add(Marker(
        markerId: const MarkerId('pickup'),
        position: LatLng(r.pickupLat!, r.pickupLng!),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        infoWindow: const InfoWindow(title: 'Pickup'),
      ));
    }
    if (r.dropoffLat != null && r.dropoffLng != null) {
      markers.add(Marker(
        markerId: const MarkerId('dropoff'),
        position: LatLng(r.dropoffLat!, r.dropoffLng!),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        infoWindow: const InfoWindow(title: 'Destination'),
      ));
    }
    return markers;
  }

  CameraPosition get _initialCamera {
    final r = _trip;
    final target = _headingToPickup && r.pickupLat != null && r.pickupLng != null
        ? LatLng(r.pickupLat!, r.pickupLng!)
        : (r.dropoffLat != null && r.dropoffLng != null
            ? LatLng(r.dropoffLat!, r.dropoffLng!)
            : (r.pickupLat != null && r.pickupLng != null ? LatLng(r.pickupLat!, r.pickupLng!) : null));
    // No resolved coordinates on this trip (an older request, or its address
    // never geocoded) — center on nothing in particular; myLocationEnabled
    // still shows the driver's own real position rather than a fabricated one.
    return CameraPosition(target: target ?? const LatLng(6.5244, 3.3792), zoom: target != null ? 13 : 11);
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
                SizedBox(
                  width: double.infinity,
                  height: 280,
                  child: GoogleMap(
                    initialCameraPosition: _initialCamera,
                    markers: _markers,
                    myLocationEnabled: true,
                    myLocationButtonEnabled: false,
                    zoomControlsEnabled: false,
                  ),
                ),
                Positioned(
                  top: 12,
                  left: 12,
                  child: CircleAvatar(
                    backgroundColor: AppColors.surfaceElevated,
                    child: IconButton(
                        icon: const Icon(Icons.shield_outlined, color: AppColors.error),
                        onPressed: () {
                          Navigator.push(context, AppPageRoute(builder: (_) => const EmergencyScreen()));
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
