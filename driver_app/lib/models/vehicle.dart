/// Real backend model — mirrors backend/prisma/schema.prisma's Vehicle +
/// VehiclePhoto, and the JSON serializeVehicle() produces in
/// backend/src/routes/vehicles.routes.ts. There is no local/mock vehicle
/// data anywhere in this app; every Vehicle instance comes from the API.
library;

enum VehicleType { sedan, suv, van, truck, motorcycle, luxury, other }

VehicleType vehicleTypeFromJson(String? value) {
  switch (value) {
    case "SEDAN":
      return VehicleType.sedan;
    case "SUV":
      return VehicleType.suv;
    case "VAN":
      return VehicleType.van;
    case "TRUCK":
      return VehicleType.truck;
    case "MOTORCYCLE":
      return VehicleType.motorcycle;
    case "LUXURY":
      return VehicleType.luxury;
    default:
      return VehicleType.other;
  }
}

String vehicleTypeToJson(VehicleType type) {
  switch (type) {
    case VehicleType.sedan:
      return "SEDAN";
    case VehicleType.suv:
      return "SUV";
    case VehicleType.van:
      return "VAN";
    case VehicleType.truck:
      return "TRUCK";
    case VehicleType.motorcycle:
      return "MOTORCYCLE";
    case VehicleType.luxury:
      return "LUXURY";
    case VehicleType.other:
      return "OTHER";
  }
}

String vehicleTypeLabel(VehicleType type) {
  switch (type) {
    case VehicleType.sedan:
      return "Sedan";
    case VehicleType.suv:
      return "SUV";
    case VehicleType.van:
      return "Van";
    case VehicleType.truck:
      return "Truck";
    case VehicleType.motorcycle:
      return "Motorcycle";
    case VehicleType.luxury:
      return "Luxury";
    case VehicleType.other:
      return "Other";
  }
}

enum VehicleVerificationStatus { pending, approved, rejected, resubmissionRequired }

VehicleVerificationStatus vehicleVerificationStatusFromJson(String? value) {
  switch (value) {
    case "APPROVED":
      return VehicleVerificationStatus.approved;
    case "REJECTED":
      return VehicleVerificationStatus.rejected;
    case "RESUBMISSION_REQUIRED":
      return VehicleVerificationStatus.resubmissionRequired;
    default:
      return VehicleVerificationStatus.pending;
  }
}

enum VehiclePhotoType { front, rear, leftSide, rightSide, interior, other }

VehiclePhotoType vehiclePhotoTypeFromJson(String? value) {
  switch (value) {
    case "FRONT":
      return VehiclePhotoType.front;
    case "REAR":
      return VehiclePhotoType.rear;
    case "LEFT_SIDE":
      return VehiclePhotoType.leftSide;
    case "RIGHT_SIDE":
      return VehiclePhotoType.rightSide;
    case "INTERIOR":
      return VehiclePhotoType.interior;
    default:
      return VehiclePhotoType.other;
  }
}

String vehiclePhotoTypeToJson(VehiclePhotoType type) {
  switch (type) {
    case VehiclePhotoType.front:
      return "FRONT";
    case VehiclePhotoType.rear:
      return "REAR";
    case VehiclePhotoType.leftSide:
      return "LEFT_SIDE";
    case VehiclePhotoType.rightSide:
      return "RIGHT_SIDE";
    case VehiclePhotoType.interior:
      return "INTERIOR";
    case VehiclePhotoType.other:
      return "OTHER";
  }
}

String vehiclePhotoTypeLabel(VehiclePhotoType type) {
  switch (type) {
    case VehiclePhotoType.front:
      return "Front";
    case VehiclePhotoType.rear:
      return "Rear";
    case VehiclePhotoType.leftSide:
      return "Left side";
    case VehiclePhotoType.rightSide:
      return "Right side";
    case VehiclePhotoType.interior:
      return "Interior";
    case VehiclePhotoType.other:
      return "Other";
  }
}

class VehiclePhoto {
  final String id;
  final String vehicleId;
  final String fileKey;
  final VehiclePhotoType photoType;
  final int displayOrder;
  final String? url;

  const VehiclePhoto({
    required this.id,
    required this.vehicleId,
    required this.fileKey,
    required this.photoType,
    required this.displayOrder,
    required this.url,
  });

  factory VehiclePhoto.fromJson(Map<String, dynamic> json) => VehiclePhoto(
        id: json['id'] as String,
        vehicleId: json['vehicleId'] as String,
        fileKey: json['fileKey'] as String,
        photoType: vehiclePhotoTypeFromJson(json['photoType'] as String?),
        displayOrder: (json['displayOrder'] as num?)?.toInt() ?? 0,
        url: json['url'] as String?,
      );
}

class Vehicle {
  final String id;
  final String driverId;
  final String brand;
  final String model;
  final String colour;
  final String plateNumber;
  final String year;
  final String? vin;
  final VehicleType vehicleType;
  final bool isPrimary;
  final bool listedForRental;
  final bool isActive;
  final VehicleVerificationStatus verificationStatus;
  final String? verificationReason;
  final List<VehiclePhoto> photos;

  const Vehicle({
    required this.id,
    required this.driverId,
    required this.brand,
    required this.model,
    required this.colour,
    required this.plateNumber,
    required this.year,
    required this.vin,
    required this.vehicleType,
    required this.isPrimary,
    required this.listedForRental,
    required this.isActive,
    required this.verificationStatus,
    required this.verificationReason,
    required this.photos,
  });

  VehiclePhoto? get primaryPhoto => photos.isEmpty ? null : photos.first;

  factory Vehicle.fromJson(Map<String, dynamic> json) => Vehicle(
        id: json['id'] as String,
        driverId: json['driverId'] as String,
        brand: json['brand'] as String,
        model: json['model'] as String,
        colour: json['colour'] as String,
        plateNumber: json['plateNumber'] as String,
        year: json['year'] as String,
        vin: json['vin'] as String?,
        vehicleType: vehicleTypeFromJson(json['vehicleType'] as String?),
        isPrimary: json['isPrimary'] as bool? ?? false,
        listedForRental: json['listedForRental'] as bool? ?? false,
        isActive: json['isActive'] as bool? ?? true,
        verificationStatus: vehicleVerificationStatusFromJson(json['verificationStatus'] as String?),
        verificationReason: json['verificationReason'] as String?,
        photos: ((json['photos'] as List?) ?? [])
            .map((p) => VehiclePhoto.fromJson(p as Map<String, dynamic>))
            .toList(),
      );
}
