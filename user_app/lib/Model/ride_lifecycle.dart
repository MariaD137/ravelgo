/// Rider-side ride lifecycle states, kept compatible with driver_app's trip
/// stages (toPickup/arrivedPickup/inProgress/arrivedDestination) so the two
/// apps can share one backend state machine when it is connected:
///   enRoute    == driver "toPickup"
///   arrived    == driver "arrivedPickup"
///   inProgress == driver "inProgress"
///   completed  == driver "arrivedDestination" -> complete
enum RideStatus {
  requested,
  matched,
  accepted,
  enRoute,
  arrived,
  inProgress,
  completed,
  cancelled,
}

extension RideStatusLabel on RideStatus {
  String get label {
    switch (this) {
      case RideStatus.requested:
        return 'Requesting ride';
      case RideStatus.matched:
        return 'Driver found';
      case RideStatus.accepted:
        return 'Driver accepted';
      case RideStatus.enRoute:
        return 'Driver en route';
      case RideStatus.arrived:
        return 'Driver has arrived';
      case RideStatus.inProgress:
        return 'Trip in progress';
      case RideStatus.completed:
        return 'Trip completed';
      case RideStatus.cancelled:
        return 'Ride cancelled';
    }
  }

  String get description {
    switch (this) {
      case RideStatus.requested:
        return 'Looking for nearby drivers...';
      case RideStatus.matched:
        return 'Choose a driver to continue';
      case RideStatus.accepted:
        return 'Your driver is getting ready';
      case RideStatus.enRoute:
        return 'Your driver is on the way to your pickup point';
      case RideStatus.arrived:
        return 'Meet your driver at the pickup point';
      case RideStatus.inProgress:
        return 'Sit back and enjoy the ride';
      case RideStatus.completed:
        return 'You have arrived at your destination';
      case RideStatus.cancelled:
        return 'This ride was cancelled';
    }
  }
}

/// A driver's offer to take the rider's request (demo data until the
/// matching backend is connected).
class RideOffer {
  final String driverName;
  final String vehicle;
  final double rating;
  final String fare;
  final int etaMinutes;
  final String avatarAsset;

  const RideOffer({
    required this.driverName,
    required this.vehicle,
    required this.rating,
    required this.fare,
    required this.etaMinutes,
    required this.avatarAsset,
  });
}
