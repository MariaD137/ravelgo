import 'package:ravelgo_driver_app/services/api_client.dart';
import 'package:ravelgo_driver_app/services/auth_service.dart';

/// The driver's backend record (GET /api/drivers/me). Name/email live on the
/// Cognito profile, not this row, so they come from AuthService.
class DriverRecord {
  final String id;
  final String status; // PENDING_REVIEW | ACTIVE | SUSPENDED
  final bool isOnline;
  final double rating;
  final int totalTrips;
  final String preferredLanguage;

  DriverRecord({
    required this.id,
    required this.status,
    required this.isOnline,
    required this.rating,
    required this.totalTrips,
    required this.preferredLanguage,
  });

  bool get isApproved => status == 'ACTIVE';

  factory DriverRecord.fromJson(Map<String, dynamic> j) => DriverRecord(
        id: '${j['id']}',
        status: '${j['status'] ?? 'PENDING_REVIEW'}',
        isOnline: j['isOnline'] == true,
        rating: (j['rating'] is num) ? (j['rating'] as num).toDouble() : 5.0,
        totalTrips: (j['totalTrips'] is num) ? (j['totalTrips'] as num).toInt() : 0,
        preferredLanguage: '${j['preferredLanguage'] ?? 'English'}',
      );
}

/// A trip from the driver's perspective (GET /api/trips/mine).
class DriverTrip {
  final String id;
  final String pickup;
  final String destination;
  final double estimatedFare;
  final double? finalFare;
  final String status;
  final DateTime requestedAt;
  final String? riderName;

  DriverTrip({
    required this.id,
    required this.pickup,
    required this.destination,
    required this.estimatedFare,
    required this.finalFare,
    required this.status,
    required this.requestedAt,
    required this.riderName,
  });

  double get fare => finalFare ?? estimatedFare;

  static double _d(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

  factory DriverTrip.fromJson(Map<String, dynamic> j) {
    String? riderName;
    final rider = j['rider'];
    if (rider is Map) {
      riderName = [rider['firstName'], rider['lastName']]
          .where((e) => e != null && '$e'.trim().isNotEmpty)
          .join(' ')
          .trim();
      if (riderName.isEmpty) riderName = null;
    }
    return DriverTrip(
      id: '${j['id']}',
      pickup: '${j['pickup'] ?? ''}',
      destination: '${j['destination'] ?? ''}',
      estimatedFare: _d(j['estimatedFare']),
      finalFare: j['finalFare'] == null ? null : _d(j['finalFare']),
      status: '${j['status'] ?? ''}',
      requestedAt: DateTime.tryParse('${j['requestedAt']}')?.toLocal() ?? DateTime.now(),
      riderName: riderName,
    );
  }
}

class Payout {
  final String id;
  final String status;
  final double amount;
  final String period;
  final DateTime createdAt;

  Payout({
    required this.id,
    required this.status,
    required this.amount,
    required this.period,
    required this.createdAt,
  });

  factory Payout.fromJson(Map<String, dynamic> j) => Payout(
        id: '${j['id']}',
        status: '${j['status'] ?? ''}',
        amount: (j['amount'] is num) ? (j['amount'] as num).toDouble() : double.tryParse('${j['amount']}') ?? 0,
        period: '${j['period'] ?? ''}',
        createdAt: DateTime.tryParse('${j['createdAt']}')?.toLocal() ?? DateTime.now(),
      );
}

class DriverDocument {
  final String id;
  final String title;
  final String status; // NOT_UPLOADED | PENDING | APPROVED | EXPIRING_SOON | REJECTED
  final DateTime? expiryDate;

  DriverDocument({required this.id, required this.title, required this.status, required this.expiryDate});

  factory DriverDocument.fromJson(Map<String, dynamic> j) => DriverDocument(
        id: '${j['id']}',
        title: '${j['title'] ?? ''}',
        status: '${j['status'] ?? 'NOT_UPLOADED'}',
        expiryDate: j['expiryDate'] == null ? null : DateTime.tryParse('${j['expiryDate']}'),
      );
}

class DriverApi {
  /// Ensure a driver profile row exists (safe to call after sign-in).
  static Future<void> provisionMe() async {
    final email = AuthService.email;
    if (email == null || email.isEmpty) return;
    await ApiClient.post('/api/drivers/me', {
      'firstName': (AuthService.givenName?.isNotEmpty ?? false) ? AuthService.givenName : 'Driver',
      'lastName': (AuthService.familyName?.isNotEmpty ?? false) ? AuthService.familyName : 'User',
      'email': email,
    });
  }

  /// The signed-in driver's backend record.
  static Future<DriverRecord> getMe() async {
    final data = await ApiClient.get('/api/drivers/me');
    return DriverRecord.fromJson(data as Map<String, dynamic>);
  }

  /// Go online / offline. Only an ACTIVE (approved) driver can go online.
  static Future<DriverRecord> setOnline(bool online) async {
    final data = await ApiClient.patch('/api/drivers/me/availability', {'isOnline': online});
    return DriverRecord.fromJson(data as Map<String, dynamic>);
  }

  /// Trips assigned to this driver, newest first.
  static Future<List<DriverTrip>> myTrips() async {
    final data = await ApiClient.get('/api/trips/mine?pageSize=50');
    final list = (data is Map ? data['data'] : data) as List? ?? const [];
    return list.whereType<Map<String, dynamic>>().map(DriverTrip.fromJson).toList();
  }

  /// Advance a trip's status (start a matched trip, complete an in-progress one).
  static Future<DriverTrip> updateTripStatus(String tripId, String status, {double? finalFare}) async {
    final data = await ApiClient.patch('/api/trips/$tripId/status', {
      'status': status,
      if (finalFare != null) 'finalFare': finalFare,
    });
    return DriverTrip.fromJson(data as Map<String, dynamic>);
  }

  /// The driver's uploaded documents and their approval status.
  static Future<List<DriverDocument>> myDocuments() async {
    final data = await ApiClient.get('/api/documents/me');
    final list = data as List? ?? const [];
    return list.whereType<Map<String, dynamic>>().map(DriverDocument.fromJson).toList();
  }

  /// The driver's payout history (earnings paid out).
  static Future<List<Payout>> payoutHistory() async {
    final data = await ApiClient.get('/api/payouts/history');
    final list = (data is Map ? (data['data'] ?? data['payouts']) : data) as List? ?? const [];
    return list.whereType<Map<String, dynamic>>().map(Payout.fromJson).toList();
  }
}
