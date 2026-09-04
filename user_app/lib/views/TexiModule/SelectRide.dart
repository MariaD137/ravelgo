import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:ravelgo_user_app/components/LocationService.dart';
import 'package:ravelgo_user_app/components/SafeGoogleMap.dart';
import 'package:ravelgo_user_app/services/api_client.dart';
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

  // Real trip geometry: pickup defaults to the device's location but the rider
  // can always override it by search (below) — destination is either an
  // address the rider searches (Places proxy) or a pin they tap on the map.
  LatLng? _pickupLatLng;
  LatLng? _destLatLng;
  double? _distanceKm;
  // Human-readable labels shown in the From/To rows and sent to the backend as
  // the trip's pickup/destination. Reverse-geocoded from coordinates.
  String? _pickupLabel;
  String? _destLabel;

  // True while the device's location is still being attempted, so we know
  // when to offer "Set pickup manually" instead of leaving the rider staring
  // at "Locating you…" forever (P0: booking dead-end when geolocation is
  // denied/unavailable — the only prior way to set pickup at all).
  bool _locatingPickup = true;

  // The real backend-computed fare for this trip, loaded once both pickup and
  // destination coordinates are known. There is only one fare per trip on the
  // backend today (a single active PricingRule) — no per-tier rate cards — so
  // this screen shows exactly one real, trustworthy price rather than
  // fabricated tier prices that would just be overwritten by the real one on
  // the next screen.
  FareQuote? _quote;
  String? _quoteError;
  bool _quoteLoading = false;

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
    if (!mounted) return;
    if (position == null) {
      // Geolocation denied/unavailable/timed out: don't leave the rider on a
      // permanently stuck "Locating you…" with no way forward. They can still
      // set pickup by search, exactly like they do for the destination.
      setState(() => _locatingPickup = false);
      return;
    }
    final me = LatLng(position.latitude, position.longitude);
    setState(() {
      _pickupLatLng = me;
      _locatingPickup = false;
      _recomputeAndQuote();
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

  /// Let the rider set pickup by search — the fallback when the device has no
  /// location (permission denied, unavailable, or they simply want to start
  /// from somewhere else). Reuses the same Places-backed search as destination.
  Future<void> _openPickupSearch() async {
    final place = await Navigator.of(context).push<PlaceLocation>(
      MaterialPageRoute(
        builder: (_) => const PlaceSearchScreen(title: 'Pickup location', hint: 'Search for a pickup address'),
      ),
    );
    if (place == null || !mounted) return;
    final pt = LatLng(place.lat, place.lng);
    setState(() {
      _pickupLatLng = pt;
      _pickupLabel = place.address;
      _recomputeAndQuote();
    });
    mapController?.animateCamera(CameraUpdate.newLatLng(pt));
  }

  void _recomputeAndQuote() {
    final from = _pickupLatLng;
    final to = _destLatLng;
    _distanceKm = (from == null || to == null)
        ? null
        : BookingApi.distanceKm(from.latitude, from.longitude, to.latitude, to.longitude);
    if (_distanceKm != null) {
      _loadQuote();
    } else {
      setState(() {
        _quote = null;
        _quoteError = null;
      });
    }
  }

  Future<void> _loadQuote() async {
    final km = _distanceKm;
    if (km == null) return;
    setState(() {
      _quoteLoading = true;
      _quoteError = null;
    });
    try {
      final q = await BookingApi.quote(distanceKm: km, durationMinutes: BookingApi.estimatedMinutes(km));
      if (!mounted) return;
      setState(() {
        _quote = q;
        _quoteLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _quoteError = e is ApiException && e.statusCode == 409
            ? 'Pricing isn\'t set up yet — please try later.'
            : 'Could not get a fare estimate.';
        _quoteLoading = false;
      });
    }
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
      _recomputeAndQuote();
    });
    mapController?.animateCamera(CameraUpdate.newLatLng(dest));
  }

  void _onMapTap(LatLng point) {
    setState(() {
      _destLatLng = point;
      _destLabel = 'Dropped pin (${point.latitude.toStringAsFixed(4)}, ${point.longitude.toStringAsFixed(4)})';
      _recomputeAndQuote();
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
      _recomputeAndQuote();
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
            for (final m in const ['Card', 'RavelGo Cash'])
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
            initialChildSize: 0.4,
            minChildSize: 0.4,
            maxChildSize: 0.7,
            builder: (_, controller) {
              return Container(
                decoration: const BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                padding: const EdgeInsets.only(left: 16, top: 12, right: 16, bottom: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Confirm your ride",
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    // From / To summary so the rider can see the pickup that was
                    // auto-detected (or set manually) and the destination they chose.
                    _buildRouteSummary(),
                    const SizedBox(height: 12),
                    Expanded(child: SingleChildScrollView(controller: controller, child: _buildFareCard())),
                    const SizedBox(height: 12),

                    // Payment row
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
                    const SizedBox(height: 12),

                    // Main CTA — a real ride, priced by the backend, or a clear
                    // reason it can't proceed yet (no fake fallback price).
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onPressed: _canProceed ? _goToFindDriver : null,
                        child: Text(_ctaLabel, style: const TextStyle(color: Colors.white)),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  bool get _canProceed => _destLatLng != null && !_quoteLoading && _quoteError == null && _quote != null;

  String get _ctaLabel {
    if (_destLatLng == null) return 'Choose a destination';
    if (_pickupLatLng == null) return 'Set your pickup';
    if (_quoteLoading) return 'Getting fare…';
    if (_quoteError != null) return 'Fare unavailable';
    return 'Confirm ride';
  }

  void _goToFindDriver() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => FindDriverScreen(
          pickup: _pickupLabel,
          destination: _destLabel ?? widget.destination,
          paymentMethod: _paymentMethod,
          distanceKm: _distanceKm,
          durationMinutes: _distanceKm == null ? null : BookingApi.estimatedMinutes(_distanceKm!),
          pickupLat: _pickupLatLng?.latitude,
          pickupLng: _pickupLatLng?.longitude,
          dropoffLat: _destLatLng?.latitude,
          dropoffLng: _destLatLng?.longitude,
        ),
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
          // Pickup row: tap to search a different pickup, always available —
          // this is what fixes the "stuck on Locating you…" dead end when
          // geolocation is denied or unavailable.
          InkWell(
            onTap: _openPickupSearch,
            child: _routeRow(
              icon: Icons.my_location,
              color: AppColors.success,
              label: _pickupLabel ?? (_locatingPickup ? 'Locating you…' : 'Tap to set your pickup'),
              muted: _pickupLabel == null,
              trailing: _locatingPickup
                  ? const SizedBox(height: 14, width: 14, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.edit_location_alt_outlined, size: 16, color: AppColors.textSecondary),
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(left: 9),
            child: Align(
              alignment: Alignment.centerLeft,
              child: SizedBox(height: 14, child: VerticalDivider(width: 2, thickness: 1, color: AppColors.border)),
            ),
          ),
          InkWell(
            onTap: _openDestinationSearch,
            child: _routeRow(
              icon: Icons.location_on,
              color: AppColors.primary,
              label: _destLabel ?? 'Choose your destination',
              muted: _destLabel == null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _routeRow({
    required IconData icon,
    required Color color,
    required String label,
    bool muted = false,
    Widget? trailing,
  }) {
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
        if (trailing != null) trailing,
      ],
    );
  }

  /// The one real ride option, priced by the backend. There is no per-tier
  /// rate card on the backend today, so this shows exactly what will be
  /// charged — never a placeholder number that gets replaced by a different
  /// real number on the next screen.
  Widget _buildFareCard() {
    if (_destLatLng == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text('Search "Where to?" above, or tap the map to drop a pin',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
      );
    }
    if (_pickupLatLng == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text('Set your pickup above to get a fare',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
      );
    }
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(12),
        color: AppColors.surface,
      ),
      child: Row(
        children: [
          const Icon(Icons.directions_car),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Ride', style: TextStyle(fontWeight: FontWeight.w600)),
                if (_distanceKm != null)
                  Text('≈ ${_distanceKm!.toStringAsFixed(1)} km',
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              ],
            ),
          ),
          if (_quoteLoading)
            const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
          else if (_quoteError != null)
            Flexible(child: Text(_quoteError!, style: const TextStyle(color: AppColors.error, fontSize: 12)))
          else if (_quote != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(Currency.format(_quote!.estimatedFare), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                if (_quote!.surgeMultiplier > 1)
                  Text('Surge ${_quote!.surgeMultiplier.toStringAsFixed(1)}x',
                      style: const TextStyle(fontSize: 11, color: AppColors.error)),
              ],
            ),
        ],
      ),
    );
  }
}
