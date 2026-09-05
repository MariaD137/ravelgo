import 'package:ravelgo_user_app/services/api_client.dart';

double _d(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

/// A package delivery request, from the sending customer's perspective. The
/// price (estimatedFare) is always computed server-side from packageSize —
/// this client never asserts a price.
class CourierRequest {
  final String id;
  final String pickupAddress;
  final String dropoffAddress;
  final String packageDescription;
  final String packageSize; // SMALL | MEDIUM | LARGE
  final String recipientName;
  final String recipientPhone;
  final double estimatedFare;
  final double? finalFare;
  final String status; // REQUESTED | MATCHED | IN_TRANSIT | DELIVERED | CANCELLED
  final DateTime requestedAt;

  CourierRequest({
    required this.id,
    required this.pickupAddress,
    required this.dropoffAddress,
    required this.packageDescription,
    required this.packageSize,
    required this.recipientName,
    required this.recipientPhone,
    required this.estimatedFare,
    required this.finalFare,
    required this.status,
    required this.requestedAt,
  });

  factory CourierRequest.fromJson(Map<String, dynamic> j) => CourierRequest(
        id: '${j['id']}',
        pickupAddress: '${j['pickupAddress'] ?? ''}',
        dropoffAddress: '${j['dropoffAddress'] ?? ''}',
        packageDescription: '${j['packageDescription'] ?? ''}',
        packageSize: '${j['packageSize'] ?? 'MEDIUM'}',
        recipientName: '${j['recipientName'] ?? ''}',
        recipientPhone: '${j['recipientPhone'] ?? ''}',
        estimatedFare: _d(j['estimatedFare']),
        finalFare: j['finalFare'] == null ? null : _d(j['finalFare']),
        status: '${j['status'] ?? ''}',
        requestedAt: DateTime.tryParse('${j['requestedAt']}')?.toLocal() ?? DateTime.now(),
      );
}

/// Package delivery, proxied through the RavelGo backend. Backed by the same
/// POST /api/courier-requests a driver later browses and accepts.
class CourierApi {
  static Future<CourierRequest> create({
    required String pickupAddress,
    required String dropoffAddress,
    required String packageDescription,
    required String packageSize,
    required String recipientName,
    required String recipientPhone,
  }) async {
    final data = await ApiClient.post('/api/courier-requests', {
      'pickupAddress': pickupAddress,
      'dropoffAddress': dropoffAddress,
      'packageDescription': packageDescription,
      'packageSize': packageSize,
      'recipientName': recipientName,
      'recipientPhone': recipientPhone,
    });
    return CourierRequest.fromJson(data as Map<String, dynamic>);
  }

  /// Current status of a single delivery request (for tracking).
  static Future<CourierRequest> status(String id) async {
    final data = await ApiClient.get('/api/courier-requests/$id');
    return CourierRequest.fromJson(data as Map<String, dynamic>);
  }

  /// All delivery requests this customer has sent (delivery history).
  static Future<List<CourierRequest>> sent() async {
    final data = await ApiClient.get('/api/courier-requests/sent');
    return ((data as List?) ?? const []).map((e) => CourierRequest.fromJson(e as Map<String, dynamic>)).toList();
  }
}
