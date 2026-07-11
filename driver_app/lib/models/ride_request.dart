class RideRequest {
  final String riderName;
  final double riderRating;
  final String pickup;
  final String destination;
  final double estimatedFare;
  final double distanceKm;
  final int etaMinutes;
  final String preferredLanguage;
  final bool quietModeRequested;
  final String? pickupNote;

  const RideRequest({
    required this.riderName,
    required this.riderRating,
    required this.pickup,
    required this.destination,
    required this.estimatedFare,
    required this.distanceKm,
    required this.etaMinutes,
    this.preferredLanguage = "English",
    this.quietModeRequested = false,
    this.pickupNote,
  });
}
