import 'package:ravelgo_driver_app/services/auth_service.dart';
import 'package:ravelgo_driver_app/services/driver_api.dart';

class DriverProfile {
  final String firstName;
  final String lastName;
  final String email;
  final String phoneNumber;
  final double rating;
  final int totalTrips;
  final String preferredLanguage;
  final bool quietModePreferred;
  final bool isOnline;
  // PENDING_REVIEW | ACTIVE | SUSPENDED, exactly as the backend's Driver.status
  // reads — or "" before the record has actually been fetched. The default is
  // deliberately empty, not PENDING_REVIEW: an unloaded/failed fetch must
  // never be rendered as if the backend had said "under review".
  final String status;
  // Per-document review state from the same GET /drivers/me response.
  final List<DriverDocument> documents;

  const DriverProfile({
    this.firstName = "Driver",
    this.lastName = "",
    this.email = "",
    this.phoneNumber = "",
    this.rating = 5.0,
    this.totalTrips = 0,
    this.preferredLanguage = "English",
    this.quietModePreferred = false,
    this.isOnline = false,
    this.status = "",
    this.documents = const [],
  });

  bool get isApproved => status == "ACTIVE";
  bool get isPendingReview => status == "PENDING_REVIEW";
  bool get isSuspended => status == "SUSPENDED";

  /// True once a real backend status has been loaded into this profile.
  bool get hasStatus => status.isNotEmpty;

  int get approvedDocumentCount => documents.where((d) => d.status == 'APPROVED').length;
  int get rejectedDocumentCount => documents.where((d) => d.status == 'REJECTED').length;
  int get pendingDocumentCount => documents.where((d) => d.status == 'PENDING').length;

  String get fullName => [firstName, lastName].where((e) => e.trim().isNotEmpty).join(' ').trim();

  /// Build a profile from the backend driver record, filling name/email from
  /// the signed-in Cognito identity (those live on the Cognito profile).
  factory DriverProfile.fromRecord(DriverRecord r) => DriverProfile(
        firstName: AuthService.givenName ?? "Driver",
        lastName: AuthService.familyName ?? "",
        email: AuthService.email ?? "",
        phoneNumber: r.phoneNumber,
        rating: r.rating,
        totalTrips: r.totalTrips,
        preferredLanguage: r.preferredLanguage,
        quietModePreferred: r.quietModePreferred,
        isOnline: r.isOnline,
        status: r.status,
        documents: r.documents,
      );

  DriverProfile copyWith({
    bool? isOnline,
    String? preferredLanguage,
    bool? quietModePreferred,
    String? status,
    List<DriverDocument>? documents,
  }) {
    return DriverProfile(
      firstName: firstName,
      lastName: lastName,
      email: email,
      phoneNumber: phoneNumber,
      rating: rating,
      totalTrips: totalTrips,
      preferredLanguage: preferredLanguage ?? this.preferredLanguage,
      quietModePreferred: quietModePreferred ?? this.quietModePreferred,
      isOnline: isOnline ?? this.isOnline,
      status: status ?? this.status,
      documents: documents ?? this.documents,
    );
  }
}
