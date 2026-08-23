enum CourierRequestStatus { awaitingCourier, inTransit, delivered, cancelled }

CourierRequestStatus courierStatusFromApi(String value) {
  switch (value) {
    case 'IN_TRANSIT':
      return CourierRequestStatus.inTransit;
    case 'DELIVERED':
      return CourierRequestStatus.delivered;
    case 'CANCELLED':
      return CourierRequestStatus.cancelled;
    case 'REQUESTED':
    case 'MATCHED':
    default:
      return CourierRequestStatus.awaitingCourier;
  }
}

class CourierRequest {
  final String id;
  final String requesterName;
  final String? courierName;
  final String pickupStation;
  final String dropoffStation;
  final double courierFare;
  final CourierRequestStatus status;

  const CourierRequest({
    required this.id,
    required this.requesterName,
    this.courierName,
    required this.pickupStation,
    required this.dropoffStation,
    required this.courierFare,
    required this.status,
  });

  /// Built from GET /api/courier-requests (Admin, paginated).
  factory CourierRequest.fromJson(Map<String, dynamic> json) {
    final sender = json['sender'] as Map<String, dynamic>?;
    final driver = json['driver'] as Map<String, dynamic>?;
    final driverUser = driver?['user'] as Map<String, dynamic>?;
    return CourierRequest(
      id: json['id'] as String,
      requesterName: sender == null ? '(unknown)' : '${sender['firstName']} ${sender['lastName']}',
      courierName: driverUser == null ? null : '${driverUser['firstName']} ${driverUser['lastName']}',
      pickupStation: json['pickupAddress'] as String,
      dropoffStation: json['dropoffAddress'] as String,
      courierFare: ((json['finalFare'] ?? json['estimatedFare']) as num).toDouble(),
      status: courierStatusFromApi(json['status'] as String),
    );
  }
}
