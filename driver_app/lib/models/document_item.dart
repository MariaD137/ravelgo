/// Real backend model — mirrors backend/prisma/schema.prisma's
/// DriverDocument. There is no local/mock document data anywhere in this
/// app; every DriverDocument instance comes from GET /api/documents/me.
library;

enum DocumentStatus { notUploaded, pending, approved, expiringSoon, rejected }

DocumentStatus documentStatusFromJson(String? value) {
  switch (value) {
    case "PENDING":
      return DocumentStatus.pending;
    case "APPROVED":
      return DocumentStatus.approved;
    case "EXPIRING_SOON":
      return DocumentStatus.expiringSoon;
    case "REJECTED":
      return DocumentStatus.rejected;
    default:
      return DocumentStatus.notUploaded;
  }
}

enum DriverDocumentType {
  driversLicense,
  vehicleRegistration,
  insurance,
  inspection,
  roadworthiness,
  backgroundCheck,
  proofOfAddress,
  other,
}

DriverDocumentType driverDocumentTypeFromJson(String? value) {
  switch (value) {
    case "DRIVERS_LICENSE":
      return DriverDocumentType.driversLicense;
    case "VEHICLE_REGISTRATION":
      return DriverDocumentType.vehicleRegistration;
    case "INSURANCE":
      return DriverDocumentType.insurance;
    case "INSPECTION":
      return DriverDocumentType.inspection;
    case "ROADWORTHINESS":
      return DriverDocumentType.roadworthiness;
    case "BACKGROUND_CHECK":
      return DriverDocumentType.backgroundCheck;
    case "PROOF_OF_ADDRESS":
      return DriverDocumentType.proofOfAddress;
    default:
      return DriverDocumentType.other;
  }
}

String driverDocumentTypeToJson(DriverDocumentType type) {
  switch (type) {
    case DriverDocumentType.driversLicense:
      return "DRIVERS_LICENSE";
    case DriverDocumentType.vehicleRegistration:
      return "VEHICLE_REGISTRATION";
    case DriverDocumentType.insurance:
      return "INSURANCE";
    case DriverDocumentType.inspection:
      return "INSPECTION";
    case DriverDocumentType.roadworthiness:
      return "ROADWORTHINESS";
    case DriverDocumentType.backgroundCheck:
      return "BACKGROUND_CHECK";
    case DriverDocumentType.proofOfAddress:
      return "PROOF_OF_ADDRESS";
    case DriverDocumentType.other:
      return "OTHER";
  }
}

String driverDocumentTypeLabel(DriverDocumentType type) {
  switch (type) {
    case DriverDocumentType.driversLicense:
      return "Driver's License";
    case DriverDocumentType.vehicleRegistration:
      return "Vehicle Registration";
    case DriverDocumentType.insurance:
      return "Insurance";
    case DriverDocumentType.inspection:
      return "Inspection";
    case DriverDocumentType.roadworthiness:
      return "Roadworthiness Certificate";
    case DriverDocumentType.backgroundCheck:
      return "Background Check";
    case DriverDocumentType.proofOfAddress:
      return "Proof of Address";
    case DriverDocumentType.other:
      return "Other Document";
  }
}

class DriverDocument {
  final String id;
  final String driverId;
  final String? vehicleId;
  final String title;
  final DriverDocumentType documentType;
  final DocumentStatus status;
  final String? fileKey;
  final DateTime? expiryDate;
  final String? rejectionReason;
  final DateTime? reviewedAt;

  const DriverDocument({
    required this.id,
    required this.driverId,
    required this.vehicleId,
    required this.title,
    required this.documentType,
    required this.status,
    required this.fileKey,
    required this.expiryDate,
    required this.rejectionReason,
    required this.reviewedAt,
  });

  bool get hasFile => fileKey != null;

  factory DriverDocument.fromJson(Map<String, dynamic> json) => DriverDocument(
        id: json['id'] as String,
        driverId: json['driverId'] as String,
        vehicleId: json['vehicleId'] as String?,
        title: json['title'] as String,
        documentType: driverDocumentTypeFromJson(json['documentType'] as String?),
        status: documentStatusFromJson(json['status'] as String?),
        fileKey: json['fileKey'] as String?,
        expiryDate: json['expiryDate'] == null ? null : DateTime.tryParse(json['expiryDate'] as String),
        rejectionReason: json['rejectionReason'] as String?,
        reviewedAt: json['reviewedAt'] == null ? null : DateTime.tryParse(json['reviewedAt'] as String),
      );
}
