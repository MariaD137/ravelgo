import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Wraps [GoogleMap]. The web build now ships the Google Maps JS SDK (the key
/// is injected into index.html at build time — see scripts/host-web-staging.sh),
/// so the real map renders on web too. If no key was provided the map area
/// simply stays blank rather than crashing.
class SafeGoogleMap extends StatelessWidget {
  const SafeGoogleMap({
    super.key,
    required this.initialCameraPosition,
    this.onMapCreated,
    this.onTap,
    this.mapType = MapType.normal,
    this.myLocationEnabled = false,
    this.myLocationButtonEnabled = true,
    this.zoomControlsEnabled = true,
    this.compassEnabled = true,
    this.markers = const {},
  });

  final CameraPosition initialCameraPosition;
  final void Function(GoogleMapController)? onMapCreated;
  final void Function(LatLng)? onTap;
  final MapType mapType;
  final bool myLocationEnabled;
  final bool myLocationButtonEnabled;
  final bool zoomControlsEnabled;
  final bool compassEnabled;
  final Set<Marker> markers;

  @override
  Widget build(BuildContext context) {
    return GoogleMap(
      mapType: mapType,
      onMapCreated: onMapCreated,
      onTap: onTap,
      initialCameraPosition: initialCameraPosition,
      myLocationEnabled: myLocationEnabled,
      myLocationButtonEnabled: myLocationButtonEnabled,
      zoomControlsEnabled: zoomControlsEnabled,
      compassEnabled: compassEnabled,
      markers: markers,
    );
  }
}
