import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:ravelgo_user_app/theme/app_theme.dart';

/// Wraps [GoogleMap] with a graceful fallback for web.
///
/// This app ships Android/iOS only (no web/ target, no key injected into a
/// web build), so on web the Google Maps JS SDK never loads and the plugin
/// throws `TypeError: Cannot read properties of undefined (reading 'maps')`
/// the moment it tries to create the map. Rather than let that crash surface
/// as Flutter's raw red error screen, show a themed placeholder on web and
/// render the real map everywhere else.
class SafeGoogleMap extends StatelessWidget {
  const SafeGoogleMap({
    super.key,
    required this.initialCameraPosition,
    this.onMapCreated,
    this.mapType = MapType.normal,
    this.myLocationEnabled = false,
    this.myLocationButtonEnabled = true,
    this.zoomControlsEnabled = true,
    this.compassEnabled = true,
    this.markers = const {},
  });

  final CameraPosition initialCameraPosition;
  final void Function(GoogleMapController)? onMapCreated;
  final MapType mapType;
  final bool myLocationEnabled;
  final bool myLocationButtonEnabled;
  final bool zoomControlsEnabled;
  final bool compassEnabled;
  final Set<Marker> markers;

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return _MapPlaceholder();
    }
    return GoogleMap(
      mapType: mapType,
      onMapCreated: onMapCreated,
      initialCameraPosition: initialCameraPosition,
      myLocationEnabled: myLocationEnabled,
      myLocationButtonEnabled: myLocationButtonEnabled,
      zoomControlsEnabled: zoomControlsEnabled,
      compassEnabled: compassEnabled,
      markers: markers,
    );
  }
}

class _MapPlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.background,
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.map_outlined, size: 40, color: AppColors.textSecondary),
          const SizedBox(height: 8),
          Text(
            "Map preview unavailable",
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
