enum RentalListingStatus { pendingApproval, approved, rejected }

RentalListingStatus rentalListingStatusFromApi(String value) {
  switch (value) {
    case 'APPROVED':
      return RentalListingStatus.approved;
    case 'REJECTED':
      return RentalListingStatus.rejected;
    case 'PENDING_APPROVAL':
    default:
      return RentalListingStatus.pendingApproval;
  }
}

class RentalListing {
  final String id;
  final String ownerName;
  final String vehicle;
  final double dailyRate;
  final String location;
  final RentalListingStatus status;

  const RentalListing({
    required this.id,
    required this.ownerName,
    required this.vehicle,
    required this.dailyRate,
    required this.location,
    required this.status,
  });

  /// Built from GET /api/rentals (Admin, all statuses).
  factory RentalListing.fromJson(Map<String, dynamic> json) {
    final driver = json['driver'] as Map<String, dynamic>?;
    final driverUser = driver?['user'] as Map<String, dynamic>?;
    final vehicle = json['vehicle'] as Map<String, dynamic>?;
    return RentalListing(
      id: json['id'] as String,
      ownerName: driverUser == null ? '(unknown)' : '${driverUser['firstName']} ${driverUser['lastName']}',
      vehicle: vehicle == null ? '(vehicle unavailable)' : '${vehicle['brand']} ${vehicle['model']} ${vehicle['year']}, ${vehicle['colour']}',
      dailyRate: (json['dailyRate'] as num).toDouble(),
      location: json['location'] as String,
      status: rentalListingStatusFromApi(json['status'] as String),
    );
  }
}
