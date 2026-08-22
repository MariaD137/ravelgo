import 'package:flutter/foundation.dart';

import '../models/driver_operational_state.dart';
import 'api/api_client.dart';
import 'api/auth_provider.dart';
import 'api/courier_api.dart';
import 'api/driver_api.dart';
import 'api/ride_api.dart';

/// The app-wide holder of the driver's own [DriverOperationalState], auth
/// session, and the domain API clients screens use to reach the backend. A
/// single shared instance (`DriverSession.instance`) rather than a new
/// state-management package — this app has none installed yet, and a
/// ChangeNotifier + ListenableBuilder (both built into the Flutter SDK) is
/// enough for one app-wide value.
///
/// The operational-state part of this is a UI convenience layer, not a
/// security boundary (Part 18): the backend independently rejects a
/// conflicting action even if this state is stale, was never updated, or
/// the UI was bypassed entirely. [reconcile] is what keeps this in sync
/// with the backend's own answer — server state always wins over whatever
/// this class currently holds (Part 19).
///
/// [instance] must be set up once via [initialize] — from main.dart's
/// composition root, with an explicit [AuthProvider] — before anything
/// reads it. There is deliberately no implicit fallback construction here:
/// that was exactly the bug (a bare `ApiClient()` defaulting to
/// DevOnlyAuthProvider, which throws in release builds the moment any
/// screen touched this class). See auth_provider.dart's
/// [createDefaultAuthProvider] for where that choice is actually made.
class DriverSession extends ChangeNotifier {
  DriverSession({required AuthProvider authProvider, required ApiClient apiClient})
    : _authProvider = authProvider,
      apiClient = apiClient,
      driverApi = DriverApi(apiClient),
      rideApi = RideApi(apiClient),
      courierApi = CourierApi(apiClient);

  static DriverSession? _instance;

  static DriverSession get instance {
    final session = _instance;
    if (session == null) {
      throw StateError(
        'DriverSession.instance was read before DriverSession.initialize() '
        'ran. Call DriverSession.initialize(...) from main() before runApp().',
      );
    }
    return session;
  }

  /// The app's composition root (main.dart) calls this exactly once, with
  /// an [AuthProvider] chosen there — never inside this class — so
  /// DriverSession itself never has to decide between a dev-only provider
  /// and a production-safe one.
  static void initialize({required AuthProvider authProvider, required ApiClient apiClient}) {
    _instance = DriverSession(authProvider: authProvider, apiClient: apiClient);
  }

  /// Test-only: allows widget/unit tests to reset the singleton between
  /// cases without depending on main()'s bootstrap sequence. Not used by
  /// any production code path.
  @visibleForTesting
  static void resetForTesting({required AuthProvider authProvider, required ApiClient apiClient}) {
    _instance = DriverSession(authProvider: authProvider, apiClient: apiClient);
  }

  /// Test-only: forces [instance] back to its "never initialized" state, so
  /// a test can verify the "read before initialize()" guard itself. Not
  /// used by any production code path.
  @visibleForTesting
  static void clearForTesting() {
    _instance = null;
  }

  final AuthProvider _authProvider;
  final ApiClient apiClient;
  final DriverApi driverApi;
  final RideApi rideApi;
  final CourierApi courierApi;

  DriverOperationalState _state = DriverOperationalState.offline;
  String? _activeAssignmentId;

  DriverOperationalState get state => _state;
  String? get activeAssignmentId => _activeAssignmentId;

  AuthStatus _authStatus = AuthStatus.unauthenticated;
  String? _authErrorMessage;

  AuthStatus get authStatus => _authStatus;
  String? get authErrorMessage => _authErrorMessage;

  /// Delegates to the injected [AuthProvider] and tracks the result as
  /// [authStatus] rather than letting navigation itself stand in for "the
  /// user is signed in." Returns whether it succeeded so the caller (the
  /// Login screen) knows whether to navigate — but the source of truth is
  /// this state, not that return value.
  Future<bool> signIn({required String username, required String password}) async {
    _authStatus = AuthStatus.authenticating;
    _authErrorMessage = null;
    notifyListeners();
    try {
      await _authProvider.login(username: username, password: password);
      _authStatus = AuthStatus.authenticated;
      notifyListeners();
      return true;
    } catch (err) {
      _authStatus = AuthStatus.authenticationFailed;
      _authErrorMessage = err.toString();
      notifyListeners();
      return false;
    }
  }

  /// Clears the session and returns operational state to offline — called
  /// on an explicit sign-out, and wired as [ApiClient.onUnauthorized] from
  /// the composition root so a 401 (an expired/revoked token) drops the app
  /// back to a signed-out state instead of silently continuing to show
  /// screens that need a session that no longer exists.
  Future<void> signOut() async {
    await _authProvider.logout();
    _authStatus = AuthStatus.unauthenticated;
    _authErrorMessage = null;
    _state = DriverOperationalState.offline;
    _activeAssignmentId = null;
    notifyListeners();
  }

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
