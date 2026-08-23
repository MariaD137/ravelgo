import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Replaces the previous static `assets/fake_map.png` placeholder. The
/// configuration seam for a real map already exists (GOOGLE_MAPS_API_KEY in
/// .env, wired through to android/local.properties and
/// ios/Flutter/Secrets.xcconfig — see their .example files) but is not
/// filled in with a real key in this environment. This widget checks that
/// honestly: when a real key is configured, it renders a genuine GoogleMap
/// centered on the driver's real current location (via geolocator, already
/// a dependency); otherwise — or if location can't be resolved — it shows a
/// plain "not available" placeholder. It never fabricates a location, a
/// route, or the appearance that live tracking is working when it isn't.
class LiveMapPreview extends StatefulWidget {
  const LiveMapPreview({super.key, this.height = 280});

  final double height;

  @override
  State<LiveMapPreview> createState() => _LiveMapPreviewState();
}

class _LiveMapPreviewState extends State<LiveMapPreview> {
  late final Future<Position> _future = _resolveLocation();

  bool get _mapsConfigured {
    if (!dotenv.isInitialized) return false;
    final key = dotenv.env['GOOGLE_MAPS_API_KEY'];
    return key != null && key.isNotEmpty && key != 'YOUR_GOOGLE_MAPS_API_KEY';
  }

  Future<Position> _resolveLocation() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw Exception('Location services are disabled.');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      throw Exception('Location permission was not granted.');
    }
    return Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high));
  }

  Widget _placeholder(String message) {
    return Container(
      width: double.infinity,
      height: widget.height,
      color: Colors.grey.shade200,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.map_outlined, size: 32, color: Colors.black38),
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: Colors.black54)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_mapsConfigured) {
      return _placeholder("Live map isn't configured yet");
    }
    return FutureBuilder<Position>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return SizedBox(
            width: double.infinity,
            height: widget.height,
            child: const Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return _placeholder("Couldn't get your location for the map");
        }
        final position = snapshot.data!;
        final target = LatLng(position.latitude, position.longitude);
        return SizedBox(
          width: double.infinity,
          height: widget.height,
          child: GoogleMap(
            initialCameraPosition: CameraPosition(target: target, zoom: 15),
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            markers: {Marker(markerId: const MarkerId('me'), position: target)},
          ),
        );
      },
    );
  }
}
