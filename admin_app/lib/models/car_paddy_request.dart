enum CarPaddyStatus { submitted, inReview, approved, rejected }

CarPaddyStatus carPaddyStatusFromApi(String value) {
  switch (value) {
    case 'IN_REVIEW':
      return CarPaddyStatus.inReview;
    case 'APPROVED':
      return CarPaddyStatus.approved;
    case 'REJECTED':
      return CarPaddyStatus.rejected;
    case 'SUBMITTED':
    default:
      return CarPaddyStatus.submitted;
  }
}

class CarPaddyRequest {
  final String id;
  final String driverName;
  final String plateNumber;
  final DateTime submittedOn;
  final CarPaddyStatus status;

  const CarPaddyRequest({
    required this.id,
    required this.driverName,
    required this.plateNumber,
    required this.submittedOn,
    required this.status,
  });

  /// Built from GET /api/car-paddy (Admin, paginated).
  factory CarPaddyRequest.fromJson(Map<String, dynamic> json) {
    final driver = json['driver'] as Map<String, dynamic>?;
    final driverUser = driver?['user'] as Map<String, dynamic>?;
    return CarPaddyRequest(
      id: json['id'] as String,
      driverName: driverUser == null ? '(unknown)' : '${driverUser['firstName']} ${driverUser['lastName']}',
      plateNumber: json['plateNumber'] as String,
      submittedOn: DateTime.parse(json['submittedAt'] as String),
      status: carPaddyStatusFromApi(json['status'] as String),
    );
  }
}
