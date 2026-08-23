/// A driver's vehicle — parsed from GET /api/vehicles/me / POST /api/vehicles's
/// real Vehicle rows.
class Vehicle {
  final String id;
  final String brand;
  final String model;
  final String colour;
  final String plateNumber;
  final String year;
  final bool isPrimary;
  final bool listedForRental;
  final String? imageUrl;

  const Vehicle({
    required this.id,
    required this.brand,
    required this.model,
    required this.colour,
    required this.plateNumber,
    required this.year,
    this.isPrimary = false,
    this.listedForRental = false,
    this.imageUrl,
  });

  factory Vehicle.fromJson(Map<String, dynamic> json) {
    return Vehicle(
      id: json['id'] as String,
      brand: json['brand'] as String? ?? '',
      model: json['model'] as String? ?? '',
      colour: json['colour'] as String? ?? '',
      plateNumber: json['plateNumber'] as String? ?? '',
      year: json['year'] as String? ?? '',
      isPrimary: json['isPrimary'] as bool? ?? false,
      listedForRental: json['listedForRental'] as bool? ?? false,
      imageUrl: json['imageUrl'] as String?,
    );
  }
}
