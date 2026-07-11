enum CarPaddyStatus { submitted, inReview, approved, rejected }

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
}

final List<CarPaddyRequest> mockCarPaddyRequests = [
  CarPaddyRequest(id: "CP-771", driverName: "Thelma Ibeh", plateNumber: "LND-482-KJ", submittedOn: DateTime.now().subtract(const Duration(days: 1)), status: CarPaddyStatus.inReview),
  CarPaddyRequest(id: "CP-770", driverName: "Chinedu Obi", plateNumber: "ABJ-119-XY", submittedOn: DateTime.now().subtract(const Duration(days: 3)), status: CarPaddyStatus.approved),
  CarPaddyRequest(id: "CP-769", driverName: "Emeka Nwosu", plateNumber: "KAN-004-ZZ", submittedOn: DateTime.now().subtract(const Duration(days: 4)), status: CarPaddyStatus.rejected),
];
