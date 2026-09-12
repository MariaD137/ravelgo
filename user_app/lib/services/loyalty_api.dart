import 'package:ravelgo_user_app/services/api_client.dart';

double _d(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

/// One rung of the loyalty ladder (GET /api/loyalty-tiers).
class LoyaltyTier {
  final String id;
  final String name;
  final int minCompletedTrips;
  final double discountPercent;
  final String? perks;
  LoyaltyTier({
    required this.id,
    required this.name,
    required this.minCompletedTrips,
    required this.discountPercent,
    this.perks,
  });

  factory LoyaltyTier.fromJson(Map<String, dynamic> j) => LoyaltyTier(
        id: '${j['id']}',
        name: '${j['name'] ?? ''}',
        minCompletedTrips: j['minCompletedTrips'] is num ? (j['minCompletedTrips'] as num).toInt() : 0,
        discountPercent: _d(j['discountPercent']),
        perks: j['perks']?.toString(),
      );
}

/// The rider's real standing (GET /api/riders/me/loyalty) — computed live
/// from actual completed trips, never stored/cached, so it can't drift.
class MyLoyalty {
  final int completedTrips;
  final LoyaltyTier? currentTier;
  MyLoyalty({required this.completedTrips, this.currentTier});

  factory MyLoyalty.fromJson(Map<String, dynamic> j) => MyLoyalty(
        completedTrips: j['completedTrips'] is num ? (j['completedTrips'] as num).toInt() : 0,
        currentTier: j['currentTier'] == null ? null : LoyaltyTier.fromJson((j['currentTier'] as Map).cast<String, dynamic>()),
      );
}

/// A redeemable promo code (GET /api/promotions).
class Promotion {
  final String code;
  final String description;
  final double discountPercent;
  final DateTime? expiresAt;
  Promotion({required this.code, required this.description, required this.discountPercent, this.expiresAt});

  factory Promotion.fromJson(Map<String, dynamic> j) => Promotion(
        code: '${j['code'] ?? ''}',
        description: '${j['description'] ?? ''}',
        discountPercent: _d(j['discountPercent']),
        expiresAt: j['expiresAt'] == null ? null : DateTime.tryParse('${j['expiresAt']}')?.toLocal(),
      );
}

class LoyaltyApi {
  static Future<List<LoyaltyTier>> tiers() async {
    final data = await ApiClient.get('/api/loyalty-tiers');
    final list = data is List ? data : const [];
    return list.whereType<Map<String, dynamic>>().map(LoyaltyTier.fromJson).toList();
  }

  static Future<MyLoyalty> myLoyalty() async {
    final data = await ApiClient.get('/api/riders/me/loyalty');
    return MyLoyalty.fromJson(data as Map<String, dynamic>);
  }

  static Future<List<Promotion>> promotions() async {
    final data = await ApiClient.get('/api/promotions');
    final list = data is List ? data : const [];
    return list.whereType<Map<String, dynamic>>().map(Promotion.fromJson).toList();
  }

  /// Redeem a promo code once. Returns the discount percent on success;
  /// throws ApiException on an invalid/expired/already-redeemed code.
  static Future<double> redeem(String code) async {
    final data = await ApiClient.post('/api/promotions/${Uri.encodeComponent(code)}/redeem');
    return _d((data as Map<String, dynamic>)['discountPercent']);
  }
}
