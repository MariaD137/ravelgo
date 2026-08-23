/// The driver's real profile — parsed from GET /api/drivers/me (which
/// includes the nested `user` relation for name/email/phone). There is no
/// default constructor with placeholder values anymore: a screen that
/// hasn't loaded real data yet must show a loading state, not "Thelma
/// Ibeh" — see driver_session.dart's `profile` getter and `loadProfile()`.
class DriverProfile {
  final String id;
  final String firstName;
  final String lastName;
  final String email;
  final String? phoneNumber;
  final double rating;
  final int totalTrips;
  final String preferredLanguage;
  final bool quietModePreferred;
  final bool isOnline;

  const DriverProfile({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.email,
    this.phoneNumber,
    required this.rating,
    required this.totalTrips,
    required this.preferredLanguage,
    required this.quietModePreferred,
    required this.isOnline,
  });

  factory DriverProfile.fromJson(Map<String, dynamic> json) {
    final user = json['user'] as Map<String, dynamic>?;
    return DriverProfile(
      id: json['id'] as String,
      firstName: user?['firstName'] as String? ?? '',
      lastName: user?['lastName'] as String? ?? '',
      email: user?['email'] as String? ?? '',
      phoneNumber: user?['phoneNumber'] as String?,
      rating: (json['rating'] as num?)?.toDouble() ?? 5.0,
      totalTrips: json['totalTrips'] as int? ?? 0,
      preferredLanguage: json['preferredLanguage'] as String? ?? 'English',
      quietModePreferred: json['quietModePreferred'] as bool? ?? false,
      isOnline: json['online'] as bool? ?? false,
    );
  }

  DriverProfile copyWith({bool? isOnline}) {
    return DriverProfile(
      id: id,
      firstName: firstName,
      lastName: lastName,
      email: email,
      phoneNumber: phoneNumber,
      rating: rating,
      totalTrips: totalTrips,
      preferredLanguage: preferredLanguage,
      quietModePreferred: quietModePreferred,
      isOnline: isOnline ?? this.isOnline,
    );
  }
}
