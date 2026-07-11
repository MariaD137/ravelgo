enum TripRecordStatus { inProgress, completed, cancelled, disputed }

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
}

final List<TripRecord> mockTripRecords = [
  TripRecord(id: "RG-10240", riderName: "Amaka Obi", driverName: "Thelma Ibeh", pickup: "Lekki Phase 1", destination: "Victoria Island", fare: 3200, date: DateTime.now().subtract(const Duration(minutes: 12)), status: TripRecordStatus.inProgress),
  TripRecord(id: "RG-10239", riderName: "Chidi Eze", driverName: "Chinedu Obi", pickup: "Ikeja City Mall", destination: "Maryland", fare: 1800, date: DateTime.now().subtract(const Duration(hours: 2)), status: TripRecordStatus.completed),
  TripRecord(id: "RG-10238", riderName: "Ngozi Peters", driverName: "Fatima Bello", pickup: "Yaba", destination: "Surulere", fare: 1500, date: DateTime.now().subtract(const Duration(hours: 5)), status: TripRecordStatus.disputed),
  TripRecord(id: "RG-10237", riderName: "Tunde Bakare", driverName: "Emeka Nwosu", pickup: "Ajah", destination: "Ikoyi", fare: 4200, date: DateTime.now().subtract(const Duration(days: 1)), status: TripRecordStatus.cancelled),
];
