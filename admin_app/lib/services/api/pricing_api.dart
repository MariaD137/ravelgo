import 'api_client.dart';

/// Admin's pricing/surge-zone management API surface — never invents fare
/// math client-side; the backend's services/pricing.ts is the single
/// source of truth (see also PricingApi in driver_app / user_app, which
/// only reads a computed quote, never writes rules).
class PricingApi {
  PricingApi(this._client);

  final ApiClient _client;

  Future<List<Map<String, dynamic>>> listPricingRules() async {
    final res = await _client.get('/api/pricing-rules');
    return (res as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> createPricingRule({
    required String name,
    required double baseFare,
    required double perKm,
    required double perMinute,
  }) async {
    return await _client.post(
          '/api/pricing-rules',
          body: {'name': name, 'baseFare': baseFare, 'perKm': perKm, 'perMinute': perMinute},
        )
        as Map<String, dynamic>;
  }

  /// Any subset of fields may be passed; only those are updated. Pass
  /// [active] to (de)activate the rule.
  Future<Map<String, dynamic>> updatePricingRule(
    String id, {
    String? name,
    double? baseFare,
    double? perKm,
    double? perMinute,
    bool? active,
  }) async {
    return await _client.patch(
          '/api/pricing-rules/$id',
          body: {
            if (name != null) 'name': name,
            if (baseFare != null) 'baseFare': baseFare,
            if (perKm != null) 'perKm': perKm,
            if (perMinute != null) 'perMinute': perMinute,
            if (active != null) 'active': active,
          },
        )
        as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> listSurgeZones() async {
    final res = await _client.get('/api/surge-zones');
    return (res as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> createSurgeZone({
    required String name,
    required String location,
    required double multiplier,
    DateTime? startsAt,
    DateTime? endsAt,
  }) async {
    return await _client.post(
          '/api/surge-zones',
          body: {
            'name': name,
            'location': location,
            'multiplier': multiplier,
            if (startsAt != null) 'startsAt': startsAt.toIso8601String(),
            if (endsAt != null) 'endsAt': endsAt.toIso8601String(),
          },
        )
        as Map<String, dynamic>;
  }

  /// Any subset of fields may be passed; only those are updated. Pass
  /// [active] to (de)activate the zone.
  Future<Map<String, dynamic>> updateSurgeZone(
    String id, {
    String? name,
    String? location,
    double? multiplier,
    DateTime? startsAt,
    DateTime? endsAt,
    bool? active,
  }) async {
    return await _client.patch(
          '/api/surge-zones/$id',
          body: {
            if (name != null) 'name': name,
            if (location != null) 'location': location,
            if (multiplier != null) 'multiplier': multiplier,
            if (startsAt != null) 'startsAt': startsAt.toIso8601String(),
            if (endsAt != null) 'endsAt': endsAt.toIso8601String(),
            if (active != null) 'active': active,
          },
        )
        as Map<String, dynamic>;
  }
}
