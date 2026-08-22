/// The single authoritative view of "what is this driver doing right now,"
/// replacing separate, independently-settable local flags
/// (e.g. an `_acceptCourier` toggle living only in one screen's own local
/// state) that could silently disagree with each other and with the
/// backend. One driver has at most one active assignment at a time — see
/// DriverAssignment in the backend's schema.prisma for the source of truth
/// this mirrors.
enum DriverOperationalState { offline, available, onRide, onCourier, onRental }

extension DriverOperationalStateX on DriverOperationalState {
  bool get isBusy => switch (this) {
    DriverOperationalState.onRide => true,
    DriverOperationalState.onCourier => true,
    DriverOperationalState.onRental => true,
    DriverOperationalState.offline => false,
    DriverOperationalState.available => false,
  };

  String get label => switch (this) {
    DriverOperationalState.offline => 'Offline',
    DriverOperationalState.available => 'Available',
    DriverOperationalState.onRide => 'On a ride',
    DriverOperationalState.onCourier => 'On a delivery',
    DriverOperationalState.onRental => 'On a rental handover',
  };
}
