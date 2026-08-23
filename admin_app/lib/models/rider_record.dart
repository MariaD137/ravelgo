enum RiderStatus { active, suspended }

class RiderTripSummary {
  final String id;
  final String pickup;
  final String destination;
  final String status;
  final DateTime requestedAt;

  const RiderTripSummary({
    required this.id,
    required this.pickup,
    required this.destination,
    required this.status,
    required this.requestedAt,
  });

  factory RiderTripSummary.fromJson(Map<String, dynamic> json) {
    return RiderTripSummary(
      id: json['id'] as String,
      pickup: json['pickup'] as String,
      destination: json['destination'] as String,
      status: json['status'] as String,
      requestedAt: DateTime.parse(json['requestedAt'] as String),
    );
  }
}

class RiderRecord {
  final String id;
  final String name;
  final String email;
  final RiderStatus status;
  final bool isLoyaltyMember;
  // Only populated from GET /api/riders/:id (detail) — the list endpoint
  // doesn't include trip history, so this is null there rather than a
  // fabricated 0/placeholder.
  final List<RiderTripSummary>? recentTrips;

  const RiderRecord({
    required this.id,
    required this.name,
    required this.email,
    required this.status,
    this.isLoyaltyMember = false,
    this.recentTrips,
  });

  /// Built from GET /api/riders (list) or GET /api/riders/:id (detail).
  factory RiderRecord.fromJson(Map<String, dynamic> json) {
    final trips = json['ridesAsRider'] as List?;
    return RiderRecord(
      id: json['id'] as String,
      name: '${json['firstName']} ${json['lastName']}',
      email: json['email'] as String,
      status: (json['suspended'] as bool? ?? false) ? RiderStatus.suspended : RiderStatus.active,
      isLoyaltyMember: json['isLoyaltyMember'] as bool? ?? false,
      recentTrips: trips?.cast<Map<String, dynamic>>().map(RiderTripSummary.fromJson).toList(),
    );
  }
}
