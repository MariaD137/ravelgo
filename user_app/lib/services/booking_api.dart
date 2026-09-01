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

  /// Request a trip. The backend computes the authoritative fare and tries to
  /// match an available driver, returning the created (and possibly MATCHED)
  /// trip.
  static Future<Trip> requestTrip({
    required String pickup,
    required String destination,
    required double distanceKm,
    required double durationMinutes,
    String category = 'Personal',
    String? zone,
    String? pickupNote,
  }) async {
    final data = await ApiClient.post('/api/trips', {
      'pickup': pickup,
      'destination': destination,
      'distanceKm': distanceKm,
      'durationMinutes': durationMinutes,
      'category': category,
      if (zone != null && zone.isNotEmpty) 'zone': zone,
      if (pickupNote != null && pickupNote.isNotEmpty) 'pickupNote': pickupNote,
    });
    return Trip.fromJson(data as Map<String, dynamic>);
  }
}
