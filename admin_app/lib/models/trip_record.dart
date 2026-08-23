enum TripRecordStatus { requested, matched, inProgress, completed, cancelled, disputed }

TripRecordStatus tripStatusFromApi(String value) {
  switch (value) {
    case 'REQUESTED':
      return TripRecordStatus.requested;
    case 'MATCHED':
      return TripRecordStatus.matched;
    case 'IN_PROGRESS':
      return TripRecordStatus.inProgress;
    case 'COMPLETED':
      return TripRecordStatus.completed;
    case 'CANCELLED':
      return TripRecordStatus.cancelled;
    case 'DISPUTED':
      return TripRecordStatus.disputed;
    default:
      return TripRecordStatus.requested;
  }
}

class TripRecord {
  final String id;
  final String riderName;
  final String driverName;
  final String pickup;
  final String destination;
  final double fare;
  final DateTime date;
  final TripRecordStatus status;

  const TripRecord({
    required this.id,
    required this.riderName,
    required this.driverName,
    required this.pickup,
    required this.destination,
    required this.fare,
    required this.date,
    required this.status,
  });

  /// Built from GET /api/trips (Admin, paginated) or GET /api/trips/:id.
  factory TripRecord.fromJson(Map<String, dynamic> json) {
    final rider = json['rider'] as Map<String, dynamic>?;
    final driver = json['driver'] as Map<String, dynamic>?;
    final driverUser = driver?['user'] as Map<String, dynamic>?;
    return TripRecord(
      id: json['id'] as String,
      riderName: rider == null ? '(unknown)' : '${rider['firstName']} ${rider['lastName']}',
      driverName: driverUser == null ? 'Unassigned' : '${driverUser['firstName']} ${driverUser['lastName']}',
      pickup: json['pickup'] as String,
      destination: json['destination'] as String,
      fare: ((json['finalFare'] ?? json['estimatedFare']) as num).toDouble(),
      date: DateTime.parse(json['requestedAt'] as String),
      status: tripStatusFromApi(json['status'] as String),
    );
  }
}
