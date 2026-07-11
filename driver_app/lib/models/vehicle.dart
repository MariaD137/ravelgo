class Vehicle {
  final String brand;
  final String model;
  final String colour;
  final String plateNumber;
  final String year;
  final bool isPrimary;
  final bool listedForRental;

  const Vehicle({
    required this.brand,
    required this.model,
    required this.colour,
    required this.plateNumber,
    required this.year,
    this.isPrimary = false,
    this.listedForRental = false,
  });
}
