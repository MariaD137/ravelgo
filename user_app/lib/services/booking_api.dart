import 'dart:math';

import 'package:ravelgo_user_app/services/api_client.dart';
import 'package:ravelgo_user_app/services/trips_api.dart';

/// A server-computed fare estimate (GET /api/pricing/quote). The fare is always
/// the backend's figure — the client never asserts a price.
class FareQuote {
  final double estimatedFare;
  final double subtotal;
  final double tax;
  final double taxRate;
  final double surgeMultiplier;
  final String? surgeZone;
  final String pricingRule;

  FareQuote({
    required this.estimatedFare,
    required this.subtotal,
    required this.tax,
    required this.taxRate,
    required this.surgeMultiplier,
    required this.surgeZone,
    required this.pricingRule,
  });

  static double _d(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

  factory FareQuote.fromJson(Map<String, dynamic> j) => FareQuote(
        estimatedFare: _d(j['estimatedFare']),
        subtotal: _d(j['subtotal']),
        tax: _d(j['tax']),
        taxRate: _d(j['taxRate']),
        surgeMultiplier: _d(j['surgeMultiplier'] ?? 1),
        surgeZone: j['surgeZone']?.toString(),
        pricingRule: '${j['pricingRule'] ?? ''}',
      );
}

/// One ride tier's rate-card-backed quote (GET /api/pricing/categories) — one
/// per active RideCategory (Swift/Ease/Luxe/Elite today). Every figure here is
/// the backend's real computation for the given trip; the client never
/// asserts a price.
class RideCategoryQuote {
  final String categoryKey;
  final String name;
  final String description;
  final String benefit;
  final double estimatedFare;
  final double subtotal;
  final double tax;
  final double taxRate;
  final double surgeMultiplier;
  final double distanceKm;
  final double tripEtaMinutes;
  // Minutes until a driver could reach the pickup — null when no eligible
  // online driver currently has a live location. Never fabricate a number
  // here; the UI must omit the pickup-ETA line instead.
  final double? pickupEtaMinutes;
  final String availability; // AVAILABLE | LIMITED | UNAVAILABLE
  final double commissionRate;

  RideCategoryQuote({
    required this.categoryKey,
    required this.name,
    required this.description,
    required this.benefit,
    required this.estimatedFare,
    required this.subtotal,
    required this.tax,
    required this.taxRate,
    required this.surgeMultiplier,
    required this.distanceKm,
    required this.tripEtaMinutes,
    required this.pickupEtaMinutes,
    required this.availability,
    required this.commissionRate,
  });

  static double _d(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
  static double? _dOrNull(dynamic v) => v == null ? null : _d(v);

  factory RideCategoryQuote.fromJson(Map<String, dynamic> j) => RideCategoryQuote(
        categoryKey: '${j['categoryKey'] ?? ''}',
        name: '${j['name'] ?? ''}',
        description: '${j['description'] ?? ''}',
        benefit: '${j['benefit'] ?? ''}',
        estimatedFare: _d(j['estimatedFare']),
        subtotal: _d(j['subtotal']),
        tax: _d(j['tax']),
        taxRate: _d(j['taxRate']),
        surgeMultiplier: _d(j['surgeMultiplier'] ?? 1),
        distanceKm: _d(j['distanceKm']),
        tripEtaMinutes: _d(j['tripEtaMinutes']),
        pickupEtaMinutes: _dOrNull(j['pickupEtaMinutes']),
        availability: '${j['availability'] ?? 'AVAILABLE'}',
        commissionRate: _d(j['commissionRate']),
      );

  bool get isUnavailable => availability == 'UNAVAILABLE';
}

class BookingApi {
  // Placeholder trip metrics. The backend needs a distance and duration to
  // price a trip, but the app has no routing/geocoding yet (the destination is
  // only a place name). These stand in until the maps/geocoding work replaces
  // them with real route figures — the fare shown is still the backend's real
  // computation for these inputs, never a client-asserted price.
  static const double placeholderDistanceKm = 6;
  static const double placeholderDurationMinutes = 18;

  /// Straight-line (great-circle) distance in km between two lat/lng points.
  /// Used to price a trip from the rider's chosen pickup and destination pins —
  /// an honest estimate for a city ride until routed distance is added.
  static double distanceKm(double lat1, double lng1, double lat2, double lng2) {
    const earthKm = 6371.0;
    double toRad(double d) => d * (pi / 180.0);
    final dLat = toRad(lat2 - lat1);
    final dLng = toRad(lng2 - lng1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(toRad(lat1)) * cos(toRad(lat2)) * sin(dLng / 2) * sin(dLng / 2);
    return earthKm * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  /// Rough trip duration for a distance, assuming ~25 km/h average city speed.
  static double estimatedMinutes(double km) => (km / 25.0) * 60.0;

  /// Live fare estimate for a trip of the given distance/duration.
  static Future<FareQuote> quote({
    required double distanceKm,
    required double durationMinutes,
    String? zone,
  }) async {
    final q = StringBuffer('/api/pricing/quote?distanceKm=$distanceKm&durationMinutes=$durationMinutes');
    if (zone != null && zone.isNotEmpty) q.write('&zone=${Uri.encodeComponent(zone)}');
    final data = await ApiClient.get(q.toString());
    return FareQuote.fromJson(data as Map<String, dynamic>);
  }

  /// Live per-tier fare estimates for a trip of the given distance/duration —
  /// one real, rate-card-backed quote per active ride category (Swift/Ease/
  /// Luxe/Elite today). Never hides a category the backend returns.
  static Future<List<RideCategoryQuote>> categories({
    required double pickupLat,
    required double pickupLng,
    required double distanceKm,
    required double durationMinutes,
    String? zone,
  }) async {
    final q = StringBuffer(
      '/api/pricing/categories?pickupLat=$pickupLat&pickupLng=$pickupLng&distanceKm=$distanceKm&durationMinutes=$durationMinutes',
    );
    if (zone != null && zone.isNotEmpty) q.write('&zone=${Uri.encodeComponent(zone)}');
    final data = await ApiClient.get(q.toString());
    return ((data as List?) ?? const [])
        .map((e) => RideCategoryQuote.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Request a trip. Pickup + dropoff COORDINATES are sent (not a distance):
  /// the backend computes the authoritative distance and fare from them and
  /// tries to match an available driver, returning the created (and possibly
  /// MATCHED) trip. A client-asserted distance is neither sent nor trusted.
  ///
  /// [rideCategoryKey], when set, prices the trip off that ride category's
  /// rate card (Swift/Ease/Luxe/Elite) instead of the legacy single
  /// PricingRule — this is what the rider chose on SelectRide.
  static Future<Trip> requestTrip({
    required String pickup,
    required String destination,
    required double pickupLat,
    required double pickupLng,
    required double dropoffLat,
    required double dropoffLng,
    String category = 'Personal',
    String? zone,
    String? pickupNote,
    String? rideCategoryKey,
  }) async {
    final data = await ApiClient.post('/api/trips', {
      'pickup': pickup,
      'destination': destination,
      'pickupLat': pickupLat,
      'pickupLng': pickupLng,
      'dropoffLat': dropoffLat,
      'dropoffLng': dropoffLng,
      'category': category,
      if (zone != null && zone.isNotEmpty) 'zone': zone,
      if (pickupNote != null && pickupNote.isNotEmpty) 'pickupNote': pickupNote,
      if (rideCategoryKey != null && rideCategoryKey.isNotEmpty) 'rideCategoryKey': rideCategoryKey,
    });
    return Trip.fromJson(data as Map<String, dynamic>);
  }

  /// Cancel a trip the rider owns (before it is under way). P0 #7 — this now
  /// calls the real backend endpoint instead of only navigating home.
  static Future<void> cancelTrip(String tripId) async {
    await ApiClient.post('/api/trips/$tripId/cancel');
  }
}
