import 'dart:math' as math;
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
  // Cash is no longer a RavelGo payment method — rides are paid by card or the
  // RavelGo wallet, both handled by the backend so the platform can take its
  // commission and pay the driver.
  String _paymentMethod = 'Card';

  // Real trip geometry: pickup defaults to the device's location but the rider
  // can always override it by search (below) — destination is always chosen
  // via the "Where to?" search (Places proxy). The map renders these same
  // coordinates as pins (see _markers/_fitCamera below); booking, distance
  // and fare are computed by the backend from them either way.
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

  // A real map showing the actual pickup/destination pins the rider has set
  // — this screen used to intentionally render a plain background instead
  // (P0: a rider booking a ride had no visual confirmation of where they
  // were actually going). Nothing here is decorative: markers only ever
  // appear once the corresponding coordinate is real.
  GoogleMapController? _mapController;

  // The real backend-computed fare per ride category (Swift/Ease/Luxe/Elite),
  // loaded once both pickup and destination coordinates are known. Each entry
  // is a real, rate-card-backed price from GET /api/pricing/categories — the
  // rider picks exactly one and that choice (categoryKey) is what flows
  // through to trip creation, so the price shown here is always what gets
  // charged (subject to re-quoting for freshness on the next screen).
  List<RideCategoryQuote> _categories = [];
  String? _categoriesError;
  bool _categoriesLoading = false;
  String? _selectedCategoryKey;

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
    _fitCamera();
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
    _fitCamera();
  }

  Set<Marker> get _markers {
    final markers = <Marker>{};
    final pickup = _pickupLatLng;
    final dest = _destLatLng;
    if (pickup != null) {
      markers.add(Marker(
        markerId: const MarkerId('pickup'),
        position: pickup,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        infoWindow: const InfoWindow(title: 'Pickup'),
      ));
    }
    if (dest != null) {
      markers.add(Marker(
        markerId: const MarkerId('destination'),
        position: dest,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        infoWindow: const InfoWindow(title: 'Destination'),
      ));
    }
    return markers;
  }

  /// Recenter the map on whatever real coordinates are currently known:
  /// both pickup and destination (fit both in view), just one (center on
  /// it), or neither yet (leave the map wherever it started). Called every
  /// time pickup/destination actually changes, never on a timer.
  void _fitCamera() {
    final controller = _mapController;
    if (controller == null) return;
    final pickup = _pickupLatLng;
    final dest = _destLatLng;
    if (pickup != null && dest != null) {
      final bounds = LatLngBounds(
        southwest: LatLng(math.min(pickup.latitude, dest.latitude), math.min(pickup.longitude, dest.longitude)),
        northeast: LatLng(math.max(pickup.latitude, dest.latitude), math.max(pickup.longitude, dest.longitude)),
      );
      controller.animateCamera(CameraUpdate.newLatLngBounds(bounds, 64));
    } else if (pickup != null) {
      controller.animateCamera(CameraUpdate.newLatLng(pickup));
    } else if (dest != null) {
      controller.animateCamera(CameraUpdate.newLatLng(dest));
    }
  }

  void _recomputeAndQuote() {
    final from = _pickupLatLng;
    final to = _destLatLng;
    _distanceKm = (from == null || to == null)
        ? null
        : BookingApi.distanceKm(from.latitude, from.longitude, to.latitude, to.longitude);
    if (_distanceKm != null) {
      _loadCategories();
    } else {
      setState(() {
        _categories = [];
        _categoriesError = null;
        _selectedCategoryKey = null;
      });
    }
  }

  Future<void> _loadCategories() async {
    final km = _distanceKm;
    final pickup = _pickupLatLng;
    if (km == null || pickup == null) return;
    setState(() {
      _categoriesLoading = true;
      _categoriesError = null;
    });
    try {
      final cats = await BookingApi.categories(
        pickupLat: pickup.latitude,
        pickupLng: pickup.longitude,
        distanceKm: km,
        durationMinutes: BookingApi.estimatedMinutes(km),
      );
      if (!mounted) return;
      setState(() {
        _categories = cats;
        _categoriesLoading = false;
        // Keep the previous selection if it's still offered; otherwise default
        // to the first available (non-UNAVAILABLE) category, if any.
        if (_selectedCategoryKey == null || !cats.any((c) => c.categoryKey == _selectedCategoryKey)) {
          final firstAvailable = cats.where((c) => !c.isUnavailable).toList();
          _selectedCategoryKey = firstAvailable.isNotEmpty ? firstAvailable.first.categoryKey : null;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _categoriesError = e is ApiException && e.statusCode == 409
            ? 'Pricing isn\'t set up yet — please try later.'
            : 'Could not get fare estimates.';
        _categoriesLoading = false;
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
    _fitCamera();
  }

  /// Refresh pickup from the device's current location (geolocator) — the
  /// same real coordinates _initPickup() uses on first load.
  Future<void> _recenterOnMe() async {
    final position = await LocationService.getCurrentLocation();
    if (position == null || !mounted) {
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
    _fitCamera();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // A real map with the pickup/destination pins the rider has actually
          // set — booking, distance and fare are still all computed by the
          // backend from the coordinates regardless of what's shown here, but
          // the rider gets visual confirmation of where they're actually going.
          Positioned.fill(
            child: SafeGoogleMap(
              initialCameraPosition: const CameraPosition(target: LatLng(6.5244, 3.3792), zoom: 12),
              markers: _markers,
              myLocationEnabled: true,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              onMapCreated: (controller) {
                _mapController = controller;
                _fitCamera();
              },
            ),
          ),

          // Top bar with back, location search, and add
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: _buildSearchBar(),
            ),
          ),

          // Refresh pickup from the device's current location.
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
                    Expanded(child: SingleChildScrollView(controller: controller, child: _buildCategoryList())),
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

  RideCategoryQuote? get _selectedCategory {
    final key = _selectedCategoryKey;
    if (key == null) return null;
    for (final c in _categories) {
      if (c.categoryKey == key) return c;
    }
    return null;
  }

  bool get _canProceed =>
      _destLatLng != null &&
      !_categoriesLoading &&
      _categoriesError == null &&
      _selectedCategory != null &&
      !_selectedCategory!.isUnavailable;

  String get _ctaLabel {
    if (_destLatLng == null) return 'Choose a destination';
    if (_pickupLatLng == null) return 'Set your pickup';
    if (_categoriesLoading) return 'Getting fares…';
    if (_categoriesError != null) return 'Fares unavailable';
    if (_selectedCategory == null) return 'Choose a ride';
    return 'Confirm ${_selectedCategory!.name}';
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
          rideCategoryKey: _selectedCategoryKey,
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

  /// A scrollable list of real ride category options, one per rate card the
  /// backend returned (GET /api/pricing/categories) — Swift/Ease/Luxe/Elite
  /// today, but this never hardcodes that set. The rider taps one to select
  /// it; that categoryKey is what flows through to trip creation, so the
  /// price shown here is always what will be charged.
  Widget _buildCategoryList() {
    if (_destLatLng == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text('Search "Where to?" above to set your destination',
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
    if (_categoriesLoading && _categories.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (_categoriesError != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(_categoriesError!, style: const TextStyle(color: AppColors.error, fontSize: 13)),
      );
    }
    if (_categories.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text('No ride options are available for this trip right now.',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
      );
    }
    return Column(
      children: [
        for (final cat in _categories) ...[
          _buildCategoryCard(cat),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  Widget _buildCategoryCard(RideCategoryQuote cat) {
    final selected = cat.categoryKey == _selectedCategoryKey;
    final unavailable = cat.isUnavailable;
    return Opacity(
      opacity: unavailable ? 0.5 : 1,
      child: InkWell(
        onTap: unavailable ? null : () => setState(() => _selectedCategoryKey = cat.categoryKey),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            border: Border.all(color: selected ? AppColors.primary : AppColors.border, width: selected ? 2 : 1),
            borderRadius: BorderRadius.circular(12),
            color: AppColors.surface,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.directions_car),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(cat.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                    if (cat.description.isNotEmpty)
                      Text(cat.description, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                    const SizedBox(height: 4),
                    Text(
                      '${cat.tripEtaMinutes.round()} min · ${cat.distanceKm.toStringAsFixed(1)} km',
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                    if (cat.pickupEtaMinutes != null)
                      Text(
                        '${cat.pickupEtaMinutes!.round()} min away',
                        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                      ),
                    if (cat.benefit.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(cat.benefit,
                            style: const TextStyle(fontSize: 11, color: AppColors.info, fontStyle: FontStyle.italic)),
                      ),
                    if (unavailable)
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Text('Unavailable right now',
                            style: TextStyle(fontSize: 11, color: AppColors.error, fontWeight: FontWeight.w600)),
                      )
                    else if (cat.availability == 'LIMITED')
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Text('Limited availability',
                            style: TextStyle(fontSize: 11, color: AppColors.warning, fontWeight: FontWeight.w600)),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(Currency.format(cat.estimatedFare), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  if (cat.surgeMultiplier > 1)
                    Text('Surge ${cat.surgeMultiplier.toStringAsFixed(1)}x',
                        style: const TextStyle(fontSize: 11, color: AppColors.error)),
                  if (selected)
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Icon(Icons.check_circle, color: AppColors.primary, size: 18),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
