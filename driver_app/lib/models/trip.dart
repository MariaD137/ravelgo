enum TripStatus { completed, cancelled, inProgress }

class Trip {
  final String id;
  final String riderName;
  final String pickup;
  final String destination;
  final double fare;
  final DateTime date;
  final TripStatus status;
  final double? riderRatingGiven;
  final String category;

  const Trip({
    required this.id,
    required this.riderName,
    required this.pickup,
    required this.destination,
    required this.fare,
    required this.date,
    required this.status,
    this.riderRatingGiven,
    this.category = "Personal",
  });
}

final List<Trip> mockTrips = [
  Trip(
    id: "RG-10234",
    riderName: "Amaka O.",
    pickup: "Lekki Phase 1",
    destination: "Victoria Island",
    fare: 3200,
    date: DateTime.now().subtract(const Duration(hours: 3)),
    status: TripStatus.completed,
    riderRatingGiven: 5,
    category: "Business",
  ),
  Trip(
    id: "RG-10229",
    riderName: "Chidi E.",
    pickup: "Ikeja City Mall",
    destination: "Maryland",
    fare: 1800,
    date: DateTime.now().subtract(const Duration(days: 1)),
    status: TripStatus.completed,
    riderRatingGiven: 4,
  ),
  Trip(
    id: "RG-10201",
    riderName: "Ngozi P.",
    pickup: "Yaba",
    destination: "Surulere",
    fare: 1500,
    date: DateTime.now().subtract(const Duration(days: 2)),
    status: TripStatus.cancelled,
  ),
];
