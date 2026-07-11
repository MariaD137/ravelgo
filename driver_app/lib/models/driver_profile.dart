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

  const DriverProfile({
    this.firstName = "Thelma",
    this.lastName = "Ibeh",
    this.email = "thelma123@gmail.com",
    this.phoneNumber = "07037530052",
    this.rating = 4.8,
    this.totalTrips = 214,
    this.preferredLanguage = "English",
    this.quietModePreferred = false,
    this.isOnline = false,
  });

  DriverProfile copyWith({bool? isOnline, String? preferredLanguage, bool? quietModePreferred}) {
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
    );
  }
}
