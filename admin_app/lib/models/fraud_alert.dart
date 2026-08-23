enum AlertStatus { open, acknowledged, resolved }

AlertStatus alertStatusFromApi(String value) {
  switch (value) {
    case 'ACKNOWLEDGED':
      return AlertStatus.acknowledged;
    case 'RESOLVED':
      return AlertStatus.resolved;
    case 'OPEN':
    default:
      return AlertStatus.open;
  }
}

/// A row from GET /api/emergency-alerts, common to both the "Fraud Alerts"
/// (type == FRAUD_SUSPECTED) and "Emergency Alerts" (type == SOS) admin
/// screens — there is no separate fraud-detection or dispatch system behind
/// either screen, just this one alert table filtered by type.
class EmergencyAlertRecord {
  final String id;
  final String personName;
  final String role;
  final String type;
  final String? message;
  final AlertStatus status;
  final DateTime createdAt;

  const EmergencyAlertRecord({
    required this.id,
    required this.personName,
    required this.role,
    required this.type,
    this.message,
    required this.status,
    required this.createdAt,
  });

  factory EmergencyAlertRecord.fromJson(Map<String, dynamic> json) {
    final user = json['user'] as Map<String, dynamic>?;
    return EmergencyAlertRecord(
      id: json['id'] as String,
      personName: user == null ? '(unknown)' : '${user['firstName']} ${user['lastName']}',
      role: user?['role'] as String? ?? 'UNKNOWN',
      type: json['type'] as String,
      message: json['message'] as String?,
      status: alertStatusFromApi(json['status'] as String),
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}
