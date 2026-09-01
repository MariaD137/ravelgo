import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:ravelgo_user_app/components/LocationService.dart';
import 'package:ravelgo_user_app/components/SafeGoogleMap.dart';
import 'package:ravelgo_user_app/services/booking_api.dart';
import 'package:ravelgo_user_app/services/places_api.dart';
import 'package:ravelgo_user_app/config/currency.dart';
import 'package:ravelgo_user_app/views/TexiModule/FindDriverScreen.dart';
import 'package:ravelgo_user_app/views/TexiModule/PlaceSearchScreen.dart';
import 'package:ravelgo_user_app/theme/app_theme.dart';

class SelectRide extends StatefulWidget {
  /// Destination chosen on the previous screen (route search); shown in the
  /// search bar so the selection visibly carries through the flow.
  final String? destination;

  /// A fully-resolved destination (address + coordinates) chosen on the
  /// previous screen. When present the trip is immediately priceable without
  /// the rider having to search or drop a pin again.
  final PlaceLocation? initialDestination;
  const SelectRide({super.key, this.destination, this.initialDestination});

  @override
  State<SelectRide> createState() => _SelectRideState();
}

class _SelectRideState extends State<SelectRide> {
  GoogleMapController? mapController;
  // Cash is no longer a RavelGo payment method — rides are paid by card or the
  // RavelGo wallet, both handled by the backend so the platform can take its
  // commission and pay the driver.
  String _paymentMethod = 'Card';
  DateTime? _scheduledFor;
  // Which ride tier the rider has selected; drives the highlighted card and the
  // CTA label so all tiers are actually pickable, not just a fixed default.
  String _selectedRide = 'Just ride';

  // Real trip geometry: pickup = device location, destination = either an
  // address the rider searches (Places proxy) or a pin they tap on the map.
  // The straight-line distance between them prices the trip.
  LatLng? _pickupLatLng;
  LatLng? _destLatLng;
  double? _distanceKm;
  // Human-readable labels shown in the From/To rows and sent to the backend as
  // the trip's pickup/destination. Reverse-geocoded from coordinates.
  String? _pickupLabel;
  String? _destLabel;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialDestination;
    if (initial != null) {
      _destLatLng = LatLng(initial.lat, initial.lng);
      _destLabel = initial.address;
    } else {
      _destLabel = widget.destination;
    }
    _initPickup();
  }

  Future<void> _initPickup() async {
    final position = await LocationService.getCurrentLocation();
    if (position == null || !mounted) return;
    final me = LatLng(position.latitude, position.longitude);
    setState(() {
      _pickupLatLng = me;
      _recompute();
    });
    mapController?.animateCamera(CameraUpdate.newLatLng(me));
    _resolvePickupLabel(me);
  }

  /// Turn the pickup coordinates into an address for the "From" line. Falls
  /// back to the raw coordinates if the geocoding proxy isn't reachable.
  Future<void> _resolvePickupLabel(LatLng me) async {
    String label = 'Current location (${me.latitude.toStringAsFixed(4)}, ${me.longitude.toStringAsFixed(4)})';
    try {
      final address = await PlacesApi.reverseGeocode(me.latitude, me.longitude);
      if (address != null && address.isNotEmpty) label = address;
    } catch (_) {
      // keep the coordinate fallback
    }
    if (mounted) setState(() => _pickupLabel = label);
  }

  void _recompute() {
    final from = _pickupLatLng;
    final to = _destLatLng;
    _distanceKm = (from == null || to == null)
        ? null
        : BookingApi.distanceKm(from.latitude, from.longitude, to.latitude, to.longitude);
  }

  /// Open the address search; on selection, drop the destination and price it.
  Future<void> _openDestinationSearch() async {
    final place = await Navigator.of(context).push<PlaceLocation>(
      MaterialPageRoute(builder: (_) => const PlaceSearchScreen()),
    );
    if (place == null || !mounted) return;
    final dest = LatLng(place.lat, place.lng);
    setState(() {
      _destLatLng = dest;
      _destLabel = place.address;
      _recompute();
    });
    mapController?.animateCamera(CameraUpdate.newLatLng(dest));
  }

  void _onMapTap(LatLng point) {
    setState(() {
      _destLatLng = point;
      _destLabel = 'Dropped pin (${point.latitude.toStringAsFixed(4)}, ${point.longitude.toStringAsFixed(4)})';
      _recompute();
    });
    // Try to upgrade the pin label to a real address in the background.
    _resolveDestLabel(point);
  }

  Future<void> _resolveDestLabel(LatLng point) async {
    try {
      final address = await PlacesApi.reverseGeocode(point.latitude, point.longitude);
      if (address != null && address.isNotEmpty && mounted && _destLatLng == point) {
        setState(() => _destLabel = address);
      }
    } catch (_) {
      // keep the coordinate label
    }
  }

  Set<Marker> _markers() {
    final m = <Marker>{};
    if (_pickupLatLng != null) {
      m.add(Marker(
        markerId: const MarkerId('pickup'),
        position: _pickupLatLng!,
        infoWindow: const InfoWindow(title: 'Pickup'),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
      ));
    }
    if (_destLatLng != null) {
      m.add(Marker(
        markerId: const MarkerId('destination'),
        position: _destLatLng!,
        infoWindow: const InfoWindow(title: 'Destination'),
      ));
    }
    return m;
  }

  /// Recenter the map on the device's real location (geolocator).
  Future<void> _recenterOnMe() async {
    final position = await LocationService.getCurrentLocation();
    if (position == null || mapController == null || !mounted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not get your location - check permissions')),
        );
      }
      return;
    }
    final me = LatLng(position.latitude, position.longitude);
    setState(() {
      _pickupLatLng = me;
      _recompute();
    });
    mapController!.animateCamera(CameraUpdate.newLatLng(me));
    _resolvePickupLabel(me);
  }

  Future<void> _pickPaymentMethod() async {
    final result = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Pay with', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            ),
            for (final m in const ['Card', 'RavelGo Wallet'])
              ListTile(
                title: Text(m),
                trailing: m == _paymentMethod
                    ? const Icon(Icons.check, color: AppColors.success)
                    : null,
                onTap: () => Navigator.pop(context, m),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (result != null) setState(() => _paymentMethod = result);
  }

  /// Schedule this ride for later (LOCAL STATE ONLY until the trips backend
  /// accepts scheduled requests).
  Future<void> _scheduleRide() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 30)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.now());
    if (time == null || !mounted) return;
    setState(() {
      _scheduledFor = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
          'Ride scheduled for ${_scheduledFor!.day}/${_scheduledFor!.month} at ${time.format(context)}'),
    ));
  }

  final LatLng _center = const LatLng(6.6018, 3.3515); // Sample: Lagos

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Google Map
          SafeGoogleMap(
            onMapCreated: (controller) => mapController = controller,
            initialCameraPosition: CameraPosition(
              target: _pickupLatLng ?? _center,
              zoom: 14.0,
            ),
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            onTap: _onMapTap,
            markers: _markers(),
          ),

          // Top bar with back, location search, and add
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: _buildSearchBar(),
            ),
          ),

          // Location button
          Positioned(
            right: 16,
            bottom: 280,
            child: CircleAvatar(
              backgroundColor: AppColors.surface,
              child: IconButton(
                icon: const Icon(Icons.my_location),
                onPressed: _recenterOnMe,
              ),
            ),
          ),

          // Bottom draggable sheet
          DraggableScrollableSheet(
            initialChildSize: 0.35,
            minChildSize: 0.35,
            maxChildSize: 0.65,
            builder: (_, controller) {
              return Container(
                decoration: const BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                padding: const EdgeInsets.only(left: 12,top: 12,right: 12),
                child: Column(
                  children: [
                    const Text(
                      "Choose a ride",
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    // From / To summary so the rider can see the pickup that was
                    // auto-detected and the destination they chose.
                    _buildRouteSummary(),
                    if (_destLatLng == null)
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Text('Search "Where to?" above, or tap the map to drop a pin',
                            style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                      )
                    else if (_distanceKm != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text('≈ ${_distanceKm!.toStringAsFixed(1)} km trip',
                            style: const TextStyle(fontSize: 12, color: AppColors.primaryDark, fontWeight: FontWeight.w600)),
                      ),
                    Expanded(
                      child: ListView(
                        controller: controller,
                        children: [
                          rideCard("Just ride", "${Currency.symbol}8,000", "2min", "4",
                              isSelected: _selectedRide == "Just ride"),
                          rideCard("EV", "${Currency.symbol}6,000", "2min", "4",
                              isSelected: _selectedRide == "EV"),
                          rideCard("Lite", "${Currency.symbol}5,000", "4min", "3",
                              isSelected: _selectedRide == "Lite"),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Payment and Delivery Row
                    Row(
                      children: [
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.surface,
                            foregroundColor: AppColors.textPrimary,
                            elevation: 0,
                            side: const BorderSide(color: AppColors.border),
                          ),
                          icon: const Icon(Icons.credit_card, size: 20),
                          label: Text(_paymentMethod),
                          onPressed: _pickPaymentMethod,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Container(
                            height: 48,
                            decoration: BoxDecoration(
                              color: AppColors.surfaceElevated,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: const Align(
                              alignment: Alignment.centerLeft,
                              child: Text("Pick up a delivery"),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Main CTA
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (context) => FindDriverScreen(
                                    pickup: _pickupLabel,
                                    destination: _destLabel ?? widget.destination,
                                    paymentMethod: _paymentMethod,
                                    distanceKm: _distanceKm,
                                    durationMinutes:
                                        _distanceKm == null ? null : BookingApi.estimatedMinutes(_distanceKm!),
                                  ),
                                ),
                              );
                            },
                            child: Text("Select $_selectedRide", style: const TextStyle(color: AppColors.textPrimary)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.textPrimary,
                            shape: const CircleBorder(),
                            padding: const EdgeInsets.all(12),
                          ),
                          onPressed: _scheduleRide,
                          child: const Icon(Icons.calendar_today, color: AppColors.surface, size: 20),
                        )
                      ],
                    ),
                    const SizedBox(height: 0),
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
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        children:  [
          IconButton(
            icon: const Icon(Icons.arrow_back,color: AppColors.textPrimary,),
            onPressed: () => Navigator.pop(context),
          ),
          const SizedBox(width: 8),
          Expanded(
            // Tapping opens the Places-backed search; the destination it returns
            // carries real coordinates so the trip can be priced and booked.
            child: InkWell(
              onTap: _openDestinationSearch,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Text(
                  _destLabel ?? "Where to?",
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    color: _destLabel == null ? AppColors.textSecondary : AppColors.textPrimary,
                  ),
                ),
              ),
            ),
          ),
          const Icon(Icons.search),
        ],
      ),
    );
  }

  Widget _buildRouteSummary() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: [
          _routeRow(
            icon: Icons.my_location,
            color: AppColors.success,
            label: _pickupLabel ?? 'Locating you…',
          ),
          const Padding(
            padding: EdgeInsets.only(left: 9),
            child: Align(
              alignment: Alignment.centerLeft,
              child: SizedBox(height: 14, child: VerticalDivider(width: 2, thickness: 1, color: AppColors.border)),
            ),
          ),
          _routeRow(
            icon: Icons.location_on,
            color: AppColors.primary,
            label: _destLabel ?? 'Choose your destination',
            muted: _destLabel == null,
          ),
        ],
      ),
    );
  }

  Widget _routeRow({required IconData icon, required Color color, required String label, bool muted = false}) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              color: muted ? AppColors.textSecondary : AppColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }

  Widget rideCard(String type, String fare, String eta, String seats, {bool isSelected = false}) {
    return GestureDetector(
      onTap: () => setState(() => _selectedRide = type),
      child: Container(
      margin: const EdgeInsets.only(bottom: 12,left: 5,right: 5),
      decoration: BoxDecoration(
        border: isSelected ? Border.all(color: AppColors.success, style: BorderStyle.solid, width: 1.5, strokeAlign: BorderSide.strokeAlignOutside) : Border.all(color: AppColors.textMuted, style: BorderStyle.solid, width: 1, strokeAlign: BorderSide.strokeAlignOutside) ,
        borderRadius: BorderRadius.circular(12),
        color: AppColors.surface,
      ),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          const Icon(Icons.directions_car),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(type, style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(eta),
                    const SizedBox(width: 8),
                    const Icon(Icons.person, size: 16),
                    Text(seats),
                  ],
                )
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(fare, style: const TextStyle(fontWeight: FontWeight.w600)),
              Text("${Currency.symbol}2,444", style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
            ],
          )
        ],
      ),
      ),
    );
  }
}