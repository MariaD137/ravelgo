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
  final String status; // PENDING_REVIEW | ACTIVE | SUSPENDED

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
    this.status = "PENDING_REVIEW",
  });

  bool get isApproved => status == "ACTIVE";

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
      );

  DriverProfile copyWith({
    bool? isOnline,
    String? preferredLanguage,
    bool? quietModePreferred,
    String? status,
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
    );
  }
}
