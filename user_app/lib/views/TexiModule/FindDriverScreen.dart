import 'package:flutter/material.dart';
import 'package:ravelgo_user_app/services/api_client.dart';
import 'package:ravelgo_user_app/services/booking_api.dart';
import 'package:ravelgo_user_app/services/places_api.dart';
import 'package:ravelgo_user_app/config/currency.dart';
import 'package:ravelgo_user_app/views/TexiModule/SearchDriverScreen.dart';
import 'package:ravelgo_user_app/theme/app_theme.dart';

class FindDriverScreen extends StatefulWidget {
  final String? pickup;
  final String? destination;
  final String paymentMethod;
  // Real trip metrics from the destination selection on SelectRide, when available.
  final double? distanceKm;
  final double? durationMinutes;
  // Pickup + dropoff coordinates — required by the backend, which computes the
  // authoritative distance/fare from them (the client no longer sends distance).
  final double? pickupLat;
  final double? pickupLng;
  final double? dropoffLat;
  final double? dropoffLng;
  // The ride category (Swift/Ease/Luxe/Elite) chosen on SelectRide, if any.
  // When set, this screen re-quotes from the SAME category-specific endpoint
  // SelectRide used (GET /api/pricing/categories) rather than the legacy
  // single-fare endpoint, so the price shown here never diverges from what
  // the rider picked. Also sent through to trip creation.
  final String? rideCategoryKey;
  const FindDriverScreen({
    super.key,
    this.pickup,
    this.destination,
    this.paymentMethod = 'Card',
    this.distanceKm,
    this.durationMinutes,
    this.pickupLat,
    this.pickupLng,
    this.dropoffLat,
    this.dropoffLng,
    this.rideCategoryKey,
  });

  @override
  State<FindDriverScreen> createState() => _FindDriverScreenState();
}

class _FindDriverScreenState extends State<FindDriverScreen> {
  String get _pickup =>
      (widget.pickup != null && widget.pickup!.trim().isNotEmpty)
          ? widget.pickup!.trim()
          : 'Current location';

  // Use the rider's map-selected distance/duration when present, else the
  // placeholder (e.g. if they skipped dropping a pin).
  double get _distanceKm => widget.distanceKm ?? BookingApi.placeholderDistanceKm;
  double get _durationMinutes => widget.durationMinutes ?? BookingApi.placeholderDurationMinutes;

  // Either a legacy single-fare quote (no category chosen) or the matching
  // entry from the same category-specific endpoint SelectRide used — never
  // both, so the shown price can't diverge between the two screens.
  FareQuote? _quote;
  RideCategoryQuote? _categoryQuote;
  String? _quoteError;
  bool _quoteLoading = true;
  bool _requesting = false;

  double get _shownFare => _categoryQuote?.estimatedFare ?? _quote?.estimatedFare ?? 0;
  double get _shownSurge => _categoryQuote?.surgeMultiplier ?? _quote?.surgeMultiplier ?? 1;

  String get _destination =>
      (widget.destination != null && widget.destination!.trim().isNotEmpty)
          ? widget.destination!.trim()
          : 'Destination';

  @override
  void initState() {
    super.initState();
    _loadQuote();
  }

  Future<void> _loadQuote() async {
    setState(() {
      _quoteLoading = true;
      _quoteError = null;
    });
    try {
      final categoryKey = widget.rideCategoryKey;
      if (categoryKey != null && categoryKey.isNotEmpty && widget.pickupLat != null && widget.pickupLng != null) {
        // A ride category was chosen on SelectRide — requote from the SAME
        // category-specific endpoint so this screen's price never diverges
        // from what the rider was shown when they picked it.
        final cats = await BookingApi.categories(
          pickupLat: widget.pickupLat!,
          pickupLng: widget.pickupLng!,
          distanceKm: _distanceKm,
          durationMinutes: _durationMinutes,
        );
        final match = cats.where((c) => c.categoryKey == categoryKey).toList();
        if (!mounted) return;
        if (match.isEmpty) {
          setState(() {
            _quoteError = 'That ride option is no longer available.';
            _quoteLoading = false;
          });
          return;
        }
        setState(() {
          _categoryQuote = match.first;
          _quote = null;
          _quoteLoading = false;
        });
      } else {
        final q = await BookingApi.quote(
          distanceKm: _distanceKm,
          durationMinutes: _durationMinutes,
        );
        if (!mounted) return;
        setState(() {
          _quote = q;
          _categoryQuote = null;
          _quoteLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _quoteError = e is ApiException && e.statusCode == 409
            ? 'Pricing isn\'t set up yet — please try later.'
            : e.toString();
        _quoteLoading = false;
      });
    }
  }

  /// Resolve the coordinates the backend needs to price the trip.
  ///
  /// Map pins are the happy path, but a rider who denied location access — or
  /// whose map never loaded — has none. Rather than dead-ending them, fall back
  /// to geocoding the address text through the backend proxy. Returns null only
  /// when even that can't place the address.
  Future<({double lat, double lng})?> _resolve(double? lat, double? lng, String address) async {
    if (lat != null && lng != null) return (lat: lat, lng: lng);
    // "Current location" is our own placeholder, not a real address — geocoding
    // it would just burn a call and fail.
    if (address.isEmpty || address == 'Current location' || address == 'Destination') return null;
    final place = await PlacesApi.forwardGeocode(address);
    if (place == null) return null;
    return (lat: place.lat, lng: place.lng);
  }

  Future<void> _findDriver() async {
    setState(() => _requesting = true);
    try {
      // The backend prices from coordinates, so resolve them first — from the
      // map pins when we have them, otherwise by geocoding what the rider typed.
      final from = await _resolve(widget.pickupLat, widget.pickupLng, _pickup);
      final to = await _resolve(widget.dropoffLat, widget.dropoffLng, _destination);
      if (!mounted) return;
      if (from == null || to == null) {
        final which = from == null ? 'pickup' : 'destination';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("We couldn't locate your $which. Pick it from the search suggestions or tap it on the map.")),
        );
        setState(() => _requesting = false);
        return;
      }
      final trip = await BookingApi.requestTrip(
        pickup: _pickup,
        destination: _destination,
        pickupLat: from.lat,
        pickupLng: from.lng,
        dropoffLat: to.lat,
        dropoffLng: to.lng,
        rideCategoryKey: widget.rideCategoryKey,
      );
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(builder: (context) => SearchDriverScreen(trip: trip)),
      );
    } catch (e) {
      if (!mounted) return;
      final msg = e is ApiException && e.statusCode == 403
          ? 'Your account isn\'t set up as a rider yet.'
          : e.toString();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      if (mounted) setState(() => _requesting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // The map is intentionally not shown here — it was purely a
          // decorative backdrop (no markers, no camera tied to the pickup/
          // dropoff pins). Pricing and booking both already resolve real
          // coordinates via PlacesApi/BookingApi regardless of whether a map
          // is rendered.
          Positioned.fill(child: Container(color: AppColors.background)),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: _buildSearchBar(),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: _buildTripInfoSheet(context),
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
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
            onPressed: () => Navigator.pop(context),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(_destination, style: const TextStyle(fontSize: 16))),
        ],
      ),
    );
  }

  Widget _buildTripInfoSheet(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [BoxShadow(color: AppColors.border, blurRadius: 10)],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildTripDetail(),
          const SizedBox(height: 16),
          _buildPaymentRow(),
          const SizedBox(height: 20),
          _buildFindDriverButton(),
        ],
      ),
    );
  }

  Widget _buildTripDetail() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Your Trip", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        const SizedBox(height: 8),
        Row(
          children: [
            Image.asset('assets/ic_pickup.png', width: 24, height: 24),
            const SizedBox(width: 8),
            Expanded(child: Text(_pickup, style: const TextStyle(fontSize: 16))),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Image.asset('assets/ic_destination.png', width: 24, height: 24),
            const SizedBox(width: 8),
            Expanded(child: Text(_destination, style: const TextStyle(fontSize: 16))),
          ],
        ),
        const SizedBox(height: 15),
        _buildFareLine(),
      ],
    );
  }

  Widget _buildFareLine() {
    if (_quoteLoading) {
      return Row(
        children: const [
          SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          SizedBox(width: 8),
          Text('Getting fare estimate…', style: TextStyle(fontSize: 14)),
        ],
      );
    }
    if (_quoteError != null) {
      return Text(_quoteError!, style: const TextStyle(color: AppColors.error, fontSize: 13));
    }
    final categoryName = _categoryQuote?.name;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (categoryName != null)
          Text(categoryName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        Text('Estimated fare: ${Currency.format(_shownFare)}',
            style: const TextStyle(color: AppColors.primaryDark, fontWeight: FontWeight.bold, fontSize: 16)),
        if (_shownSurge > 1)
          Text('Surge ${_shownSurge.toStringAsFixed(1)}x in effect',
              style: const TextStyle(color: AppColors.error, fontSize: 12)),
      ],
    );
  }

  Widget _buildPaymentRow() {
    return Row(
      children: [
        const Icon(Icons.credit_card, size: 20),
        const SizedBox(width: 8),
        Text(widget.paymentMethod),
        const Spacer(),
      ],
    );
  }

  Widget _buildFindDriverButton() {
    final canRequest = !_requesting && !_quoteLoading && _quoteError == null;
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: canRequest ? _findDriver : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        child: _requesting
            ? const SizedBox(
                height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Text("Find a driver", style: TextStyle(fontSize: 16)),
      ),
    );
  }
}
