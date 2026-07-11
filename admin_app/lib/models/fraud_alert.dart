enum AlertSeverity { low, medium, high }

class FraudAlert {
  final String id;
  final String title;
  final String description;
  final AlertSeverity severity;
  final DateTime detectedAt;

  const FraudAlert({
    required this.id,
    required this.title,
    required this.description,
    required this.severity,
    required this.detectedAt,
  });
}

final List<FraudAlert> mockFraudAlerts = [
  FraudAlert(id: "FA-901", title: "Unusual booking pattern", description: "Driver DRV-1044 accepted and cancelled 6 trips within 10 minutes.", severity: AlertSeverity.high, detectedAt: DateTime.now().subtract(const Duration(minutes: 40))),
  FraudAlert(id: "FA-900", title: "GPS spoofing suspected", description: "Trip RG-10238 shows a route inconsistent with reported distance.", severity: AlertSeverity.medium, detectedAt: DateTime.now().subtract(const Duration(hours: 3))),
  FraudAlert(id: "FA-899", title: "Duplicate account signals", description: "Rider USR-5083 device fingerprint matches 3 other suspended accounts.", severity: AlertSeverity.medium, detectedAt: DateTime.now().subtract(const Duration(hours: 8))),
];

class EmergencyAlert {
  final String id;
  final String personName;
  final String role;
  final String location;
  final DateTime triggeredAt;
  final bool resolved;

  const EmergencyAlert({
    required this.id,
    required this.personName,
    required this.role,
    required this.location,
    required this.triggeredAt,
    this.resolved = false,
  });
}

final List<EmergencyAlert> mockEmergencyAlerts = [
  EmergencyAlert(id: "SOS-221", personName: "Thelma Ibeh", role: "Driver", location: "Ozumba Mbadiwe Ave, VI", triggeredAt: DateTime.now().subtract(const Duration(minutes: 6))),
  EmergencyAlert(id: "SOS-220", personName: "Chidi Eze", role: "Rider", location: "Yaba Bridge", triggeredAt: DateTime.now().subtract(const Duration(hours: 5)), resolved: true),
];
