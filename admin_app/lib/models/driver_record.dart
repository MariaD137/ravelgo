enum DriverStatus { active, pendingReview, suspended }

class DriverRecord {
  final String id;
  final String name;
  final String email;
  final String vehicle;
  final double rating;
  final int totalTrips;
  final DriverStatus status;
  final bool subscriptionActive;

  const DriverRecord({
    required this.id,
    required this.name,
    required this.email,
    required this.vehicle,
    required this.rating,
    required this.totalTrips,
    required this.status,
    this.subscriptionActive = true,
  });
}

final List<DriverRecord> mockDrivers = [
  DriverRecord(id: "DRV-1042", name: "Thelma Ibeh", email: "thelma123@gmail.com", vehicle: "Toyota Camry", rating: 4.8, totalTrips: 214, status: DriverStatus.active),
  DriverRecord(id: "DRV-1043", name: "Chinedu Obi", email: "chinedu.o@gmail.com", vehicle: "Honda Accord", rating: 4.6, totalTrips: 132, status: DriverStatus.active),
  DriverRecord(id: "DRV-1044", name: "Fatima Bello", email: "fatima.bello@gmail.com", vehicle: "Kia Rio", rating: 4.9, totalTrips: 301, status: DriverStatus.pendingReview, subscriptionActive: false),
  DriverRecord(id: "DRV-1045", name: "Emeka Nwosu", email: "emeka.n@gmail.com", vehicle: "Hyundai Elantra", rating: 3.9, totalTrips: 58, status: DriverStatus.suspended, subscriptionActive: false),
];
