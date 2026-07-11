enum RiderStatus { active, suspended }

class RiderRecord {
  final String id;
  final String name;
  final String email;
  final int totalTrips;
  final double rating;
  final RiderStatus status;
  final bool isLoyaltyMember;

  const RiderRecord({
    required this.id,
    required this.name,
    required this.email,
    required this.totalTrips,
    required this.rating,
    required this.status,
    this.isLoyaltyMember = false,
  });
}

final List<RiderRecord> mockRiders = [
  RiderRecord(id: "USR-5081", name: "Amaka Obi", email: "amaka.obi@gmail.com", totalTrips: 63, rating: 4.9, status: RiderStatus.active, isLoyaltyMember: true),
  RiderRecord(id: "USR-5082", name: "Chidi Eze", email: "chidi.eze@gmail.com", totalTrips: 21, rating: 4.7, status: RiderStatus.active),
  RiderRecord(id: "USR-5083", name: "Ngozi Peters", email: "ngozi.p@gmail.com", totalTrips: 8, rating: 3.2, status: RiderStatus.suspended),
];
