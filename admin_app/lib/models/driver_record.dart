enum DriverStatus { active, pendingReview, suspended }

DriverStatus driverStatusFromApi(String value) {
  switch (value) {
    case 'ACTIVE':
      return DriverStatus.active;
    case 'SUSPENDED':
      return DriverStatus.suspended;
    case 'PENDING_REVIEW':
    default:
      return DriverStatus.pendingReview;
  }
}

String driverStatusToApi(DriverStatus status) {
  switch (status) {
    case DriverStatus.active:
      return 'ACTIVE';
    case DriverStatus.suspended:
      return 'SUSPENDED';
    case DriverStatus.pendingReview:
      return 'PENDING_REVIEW';
  }
}

class DriverDocumentRecord {
  final String id;
  final String title;
  final String status;

  const DriverDocumentRecord({required this.id, required this.title, required this.status});

  factory DriverDocumentRecord.fromJson(Map<String, dynamic> json) {
    return DriverDocumentRecord(
      id: json['id'] as String,
      title: json['title'] as String,
      status: json['status'] as String,
    );
  }

  bool get isApproved => status == 'APPROVED';
}

class DriverRecord {
  final String id;
  final String name;
  final String email;
  final String vehicle;
  final double rating;
  final int totalTrips;
  final DriverStatus status;
  final bool subscriptionActive;
  final List<DriverDocumentRecord> documents;

  const DriverRecord({
    required this.id,
    required this.name,
    required this.email,
    required this.vehicle,
    required this.rating,
    required this.totalTrips,
    required this.status,
    this.subscriptionActive = false,
    this.documents = const [],
  });

  /// Built from GET /api/drivers (list) or GET /api/drivers/:id (detail,
  /// which also includes `documents`) — never from invented/local data.
  factory DriverRecord.fromJson(Map<String, dynamic> json) {
    final user = json['user'] as Map<String, dynamic>?;
    final vehicles = (json['vehicles'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    final primaryVehicle = vehicles.isEmpty
        ? null
        : (vehicles.firstWhere((v) => v['isPrimary'] == true, orElse: () => vehicles.first));
    final documentsJson = (json['documents'] as List?)?.cast<Map<String, dynamic>>() ?? const [];

    return DriverRecord(
      id: json['id'] as String,
      name: user == null ? '(unknown)' : '${user['firstName']} ${user['lastName']}',
      email: user?['email'] as String? ?? '',
      vehicle: primaryVehicle == null ? 'No vehicle on file' : '${primaryVehicle['brand']} ${primaryVehicle['model']}',
      rating: (json['rating'] as num?)?.toDouble() ?? 5.0,
      totalTrips: (json['totalTrips'] as num?)?.toInt() ?? 0,
      status: driverStatusFromApi(json['status'] as String? ?? 'PENDING_REVIEW'),
      subscriptionActive: json['subscriptionActive'] as bool? ?? false,
      documents: documentsJson.map(DriverDocumentRecord.fromJson).toList(),
    );
  }
}
