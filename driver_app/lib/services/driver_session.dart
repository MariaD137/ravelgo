import 'package:flutter/foundation.dart';

import '../models/driver_operational_state.dart';
import 'api/api_client.dart';
import 'api/courier_api.dart';
import 'api/driver_api.dart';
import 'api/ride_api.dart';

/// The app-wide holder of the driver's own [DriverOperationalState] and the
/// domain API clients screens use to reach the backend. A single shared
/// instance (`DriverSession.instance`) rather than a new state-management
/// package — this app has none installed yet, and a ChangeNotifier +
/// ListenableBuilder (both built into the Flutter SDK) is enough for one
/// app-wide value.
///
/// This is a UI convenience layer, not a security boundary (Part 18): the
/// backend independently rejects a conflicting action even if this state is
/// stale, was never updated, or the UI was bypassed entirely. [reconcile]
/// is what keeps this in sync with the backend's own answer — server state
/// always wins over whatever this class currently holds (Part 19).
class DriverSession extends ChangeNotifier {
  DriverSession._internal()
    : apiClient = _sharedClient,
      driverApi = DriverApi(_sharedClient),
      rideApi = RideApi(_sharedClient),
      courierApi = CourierApi(_sharedClient);

  static final ApiClient _sharedClient = ApiClient();
  static final DriverSession instance = DriverSession._internal();

  final ApiClient apiClient;
  final DriverApi driverApi;
  final RideApi rideApi;
  final CourierApi courierApi;

  DriverOperationalState _state = DriverOperationalState.offline;
  String? _activeAssignmentId;

  DriverOperationalState get state => _state;
  String? get activeAssignmentId => _activeAssignmentId;

  void goOffline() {
    _state = DriverOperationalState.offline;
    _activeAssignmentId = null;
    notifyListeners();
  }

  void goAvailable() {
    _state = DriverOperationalState.available;
    _activeAssignmentId = null;
    notifyListeners();
  }

  void markBusy(DriverOperationalState busyState, String assignmentId) {
    assert(busyState.isBusy, 'markBusy requires a busy state, got $busyState');
    _state = busyState;
    _activeAssignmentId = assignmentId;
    notifyListeners();
  }

  /// Reconciles local state to what the backend just said — call this after
  /// any successful accept/status-update call, and after a DRIVER_BUSY 409
  /// so the UI reflects the assignment that actually won the race rather
  /// than whatever this client last assumed.
  void reconcile({required bool busy, String? assignmentType, String? assignmentId}) {
    if (!busy) {
      if (_state != DriverOperationalState.offline) goAvailable();
      return;
    }
    switch (assignmentType) {
      case 'RIDE':
        markBusy(DriverOperationalState.onRide, assignmentId ?? '');
        break;
      case 'COURIER':
        markBusy(DriverOperationalState.onCourier, assignmentId ?? '');
        break;
      case 'RENTAL':
        markBusy(DriverOperationalState.onRental, assignmentId ?? '');
        break;
    }
  }
}
