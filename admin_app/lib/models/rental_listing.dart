enum RentalListingStatus { pendingApproval, approved, rejected }

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
}

final List<RentalListing> mockRentalListings = [
  RentalListing(id: "LX-201", ownerName: "Thelma Ibeh", vehicle: "Toyota Camry 2021, Black", dailyRate: 25000, location: "Lekki Phase 1", status: RentalListingStatus.pendingApproval),
  RentalListing(id: "LX-198", ownerName: "Premier Car Rentals Ltd", vehicle: "Mercedes-Benz C300, White", dailyRate: 65000, location: "Victoria Island", status: RentalListingStatus.approved),
  RentalListing(id: "LX-193", ownerName: "Fatima Bello", vehicle: "Kia Rio 2020, Silver", dailyRate: 18000, location: "Ikeja", status: RentalListingStatus.rejected),
];
