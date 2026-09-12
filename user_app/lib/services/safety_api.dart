import 'package:ravelgo_user_app/services/api_client.dart';

/// A raised safety/fraud alert (GET /api/emergency-alerts/mine).
class EmergencyAlert {
  final String id;
  final String type; // SOS | FRAUD_SUSPECTED
  final String? message;
  final String status; // OPEN | ACKNOWLEDGED | RESOLVED
  final DateTime createdAt;
  EmergencyAlert({required this.id, required this.type, this.message, required this.status, required this.createdAt});

  factory EmergencyAlert.fromJson(Map<String, dynamic> j) => EmergencyAlert(
        id: '${j['id']}',
        type: '${j['type'] ?? ''}',
        message: j['message']?.toString(),
        status: '${j['status'] ?? 'OPEN'}',
        createdAt: DateTime.tryParse('${j['createdAt']}')?.toLocal() ?? DateTime.now(),
      );
}

class SafetyApi {
  /// Raise a real emergency alert. Admins are notified immediately
  /// (lib/notifications.ts#notifyAllAdmins) — this is not a local-only
  /// action. [tripId] ties it to an active trip when one is known.
  static Future<EmergencyAlert> raiseSos({String? tripId, String? message}) async {
    final data = await ApiClient.post('/api/emergency-alerts', {
      'type': 'SOS',
      if (tripId != null) 'tripId': tripId,
      if (message != null && message.isNotEmpty) 'message': message,
    });
    return EmergencyAlert.fromJson(data as Map<String, dynamic>);
  }

  static Future<List<EmergencyAlert>> myAlerts() async {
    final data = await ApiClient.get('/api/emergency-alerts/mine');
    final list = data is List ? data : const [];
    return list.whereType<Map<String, dynamic>>().map(EmergencyAlert.fromJson).toList();
  }
}
