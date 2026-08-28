import 'package:flutter/foundation.dart';

import 'package:ravelgo_admin/models/car_paddy_request.dart';
import 'package:ravelgo_admin/models/rental_listing.dart';

/// LOCAL STATE ONLY: records administrative decisions made this session as
/// overlays keyed by entity id, without mutating the immutable demo data.
/// Each map mirrors the PATCH/POST an admin backend would receive - the
/// integration point is to replace these writes with API calls and refresh.
/// NOTHING here executes a real refund, suspension, or approval on a
/// backend; the UI communicates that at each action.
class AdminActionsState extends ChangeNotifier {
  AdminActionsState._();
  static final AdminActionsState instance = AdminActionsState._();

  // Trips
  final Set<String> refundRequestedTrips = {};
  final Set<String> resolvedTrips = {};
  final Set<String> flaggedTrips = {};

  void requestRefund(String tripId) {
    refundRequestedTrips.add(tripId);
    notifyListeners();
  }

  void resolveTrip(String tripId) {
    resolvedTrips.add(tripId);
    notifyListeners();
  }

  void flagTrip(String tripId) {
    flaggedTrips.add(tripId);
    notifyListeners();
  }

  // Rental listings
  final Map<String, RentalListingStatus> rentalDecisions = {};

  RentalListingStatus effectiveRentalStatus(RentalListing l) =>
      rentalDecisions[l.id] ?? l.status;

  void decideRental(String id, RentalListingStatus status) {
    rentalDecisions[id] = status;
    notifyListeners();
  }

  // Car Paddy requests
  final Map<String, CarPaddyStatus> carPaddyDecisions = {};

  CarPaddyStatus effectiveCarPaddyStatus(CarPaddyRequest r) =>
      carPaddyDecisions[r.id] ?? r.status;

  void decideCarPaddy(String id, CarPaddyStatus status) {
    carPaddyDecisions[id] = status;
    notifyListeners();
  }

  // Fraud alerts: 'dismissed' or 'investigating'
  final Map<String, String> fraudDecisions = {};

  void decideFraud(String id, String decision) {
    fraudDecisions[id] = decision;
    notifyListeners();
  }

  // Emergency alerts resolved this session
  final Set<String> resolvedEmergencies = {};

  void resolveEmergency(String id) {
    resolvedEmergencies.add(id);
    notifyListeners();
  }
}
