enum CourierRequestStatus { awaitingCourier, inTransit, delivered, cancelled }

class CourierRequest {
  final String id;
  final String requesterName;
  final String? courierName;
  final String pickupStation;
  final String dropoffStation;
  final double fixedFee;
  final double courierFare;
  final CourierRequestStatus status;

  const CourierRequest({
    required this.id,
    required this.requesterName,
    this.courierName,
    required this.pickupStation,
    required this.dropoffStation,
    required this.fixedFee,
    required this.courierFare,
    required this.status,
  });
}

final List<CourierRequest> mockCourierRequests = [
  CourierRequest(id: "CR-3301", requesterName: "Amaka Obi", courierName: "Bisi Adewale", pickupStation: "Lekki Station A", dropoffStation: "Ikeja Station C", fixedFee: 500, courierFare: 2200, status: CourierRequestStatus.inTransit),
  CourierRequest(id: "CR-3300", requesterName: "Tunde Bakare", pickupStation: "Yaba Station B", dropoffStation: "Surulere Station A", fixedFee: 500, courierFare: 1600, status: CourierRequestStatus.awaitingCourier),
  CourierRequest(id: "CR-3298", requesterName: "Chidi Eze", courierName: "Kunle Ade", pickupStation: "VI Station A", dropoffStation: "Ajah Station D", fixedFee: 500, courierFare: 2600, status: CourierRequestStatus.delivered),
];
