import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/driver_operational_state.dart';
import '../models/driver_profile.dart';
import 'api/api_client.dart';
import 'api/auth_provider.dart';
import 'api/courier_api.dart';
import 'api/document_api.dart';
import 'api/driver_api.dart';
import 'api/ride_api.dart';
import 'api/vehicle_api.dart';

/// The app-wide holder of the driver's own [DriverOperationalState], real
/// profile, real-time presence, current ride assignment, auth session, and
/// the domain API clients screens use to reach the backend. A single
/// shared instance (`DriverSession.instance`) rather than a new
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
/// Ride matching has no "browse and accept" step on the backend — a driver
/// is matched synchronously and atomically by services/matching.ts, with
/// no offer a second driver could also be racing for (see
/// DRIVER_APP_REAL_MATCHING_READINESS.md's API MAP section). This class's
/// [_pollForAssignment] loop and best-effort WebSocket connection are how a
/// driver discovers a match happened at all, not a client-side matching
/// engine — every decision (who gets matched, whether a transition is
/// legal) is made and enforced by the backend; this class only asks it and
/// mirrors the answer.
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
      courierApi = CourierApi(apiClient),
      vehicleApi = VehicleApi(apiClient),
      documentApi = DocumentApi(apiClient);

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
    _instance?._stopAssignmentTracking();
    _instance = DriverSession(authProvider: authProvider, apiClient: apiClient);
  }

  /// Test-only: forces [instance] back to its "never initialized" state, so
  /// a test can verify the "read before initialize()" guard itself. Not
  /// used by any production code path.
  @visibleForTesting
  static void clearForTesting() {
    _instance?._stopAssignmentTracking();
    _instance = null;
  }

  final AuthProvider _authProvider;
  final ApiClient apiClient;
  final DriverApi driverApi;
  final RideApi rideApi;
  final CourierApi courierApi;
  final VehicleApi vehicleApi;
  final DocumentApi documentApi;

  DriverOperationalState _state = DriverOperationalState.offline;
  String? _activeAssignmentId;

  DriverOperationalState get state => _state;
  String? get activeAssignmentId => _activeAssignmentId;

  AuthStatus _authStatus = AuthStatus.unauthenticated;
  String? _authErrorMessage;

  AuthStatus get authStatus => _authStatus;
  String? get authErrorMessage => _authErrorMessage;

  DriverProfile? _profile;
  DriverProfile? get profile => _profile;

  /// Full Trip JSON for a ride the backend just matched to this driver,
  /// discovered via polling/WS and not yet acted on (accepted or
  /// declined). Null the rest of the time. Driver-facing screens
  /// (driver_home_screen.dart) show the incoming-request sheet exactly
  /// when this is non-null — never on a local timer or a "simulate"
  /// button.
  Map<String, dynamic>? _pendingRideAssignment;
  Map<String, dynamic>? get pendingRideAssignment => _pendingRideAssignment;

  bool _assignmentActionInFlight = false;
  bool get assignmentActionInFlight => _assignmentActionInFlight;

  Timer? _pollTimer;
  WebSocketChannel? _ws;
  StreamSubscription? _wsSub;
  String? _lastSeenAssignmentId;

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
    _stopAssignmentTracking();
    await _authProvider.logout();
    _authStatus = AuthStatus.unauthenticated;
    _authErrorMessage = null;
    _state = DriverOperationalState.offline;
    _activeAssignmentId = null;
    _profile = null;
    _pendingRideAssignment = null;
    notifyListeners();
  }

  /// Loads the driver's real profile (GET /api/drivers/me). Returns false
  /// (and leaves [profile] null) on a 404 — no backend Driver row yet —
  /// rather than falling back to placeholder data; the caller is expected
  /// to show an honest "complete driver onboarding" state in that case.
  Future<bool> loadProfile() async {
    try {
      final json = await driverApi.getMyProfile();
      _profile = DriverProfile.fromJson(json);
      if (_profile!.isOnline && !_state.isBusy) {
        _state = DriverOperationalState.available;
      }
      notifyListeners();
      return true;
    } on ApiException catch (err) {
      if (err.statusCode == 404) {
        _profile = null;
        notifyListeners();
        return false;
      }
      rethrow;
    }
  }

  /// Goes online: PATCH /api/drivers/me/online, then starts polling (and a
  /// best-effort WebSocket) for a new ride assignment. Returns false (and
  /// leaves state unchanged) on failure — the switch in the UI must never
  /// show "online" unless the backend actually agrees. Distinct from
  /// [goAvailable] (a pure local state setter, used internally by
  /// [reconcile] and by tests that don't need a real backend call).
  Future<bool> setOnline() async {
    try {
      final json = await driverApi.setOnline(true);
      _profile = _profile?.copyWith(isOnline: true) ?? DriverProfile.fromJson(json);
      if (!_state.isBusy) goAvailable();
      _startAssignmentTracking();
      return true;
    } on ApiException catch (err) {
      _authErrorMessage = err.message;
      notifyListeners();
      return false;
    }
  }

  /// Goes offline: PATCH /api/drivers/me/online, then stops assignment
  /// tracking. A driver mid-job (busy) who goes offline keeps their busy
  /// state — going offline only ever affects whether they're eligible for
  /// a *new* match, never an assignment already in progress. Distinct from
  /// [goOffline] (a pure local state setter) for the same reason as
  /// [setOnline]/[goAvailable] above.
  Future<bool> setOffline() async {
    try {
      final json = await driverApi.setOnline(false);
      _profile = _profile?.copyWith(isOnline: false) ?? DriverProfile.fromJson(json);
      if (!_state.isBusy) goOffline();
      _stopAssignmentTracking();
      return true;
    } on ApiException catch (err) {
      _authErrorMessage = err.message;
      notifyListeners();
      return false;
    }
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
    // A busy driver can't be matched to anything new (matching.ts excludes
    // them) — no point polling/holding a WS connection open for a new
    // assignment until they're free again.
    _stopAssignmentTracking();
    notifyListeners();
  }

  /// Reconciles local state to what the backend just said — call this after
  /// any successful accept/status-update call, and after a DRIVER_BUSY 409
  /// so the UI reflects the assignment that actually won the race rather
  /// than whatever this client last assumed.
  void reconcile({required bool busy, String? assignmentType, String? assignmentId}) {
    if (!busy) {
      if (_state != DriverOperationalState.offline) {
        _state = DriverOperationalState.available;
        _activeAssignmentId = null;
        notifyListeners();
        if (_profile?.isOnline == true) _startAssignmentTracking();
      }
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

  // --- Ride assignment discovery (polling primary + WS overlay) ------------

  void _startAssignmentTracking() {
    _pollTimer?.cancel();
    // Polling is the primary, always-correct mechanism — matching is
    // synchronous server-side with no client push required to work at
    // all; the WebSocket connection below is a best-effort latency
    // improvement on top of it, never a replacement for it.
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) => _poll());
    unawaited(_poll());
    unawaited(_connectWs());
  }

  void _stopAssignmentTracking() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _wsSub?.cancel();
    _wsSub = null;
    _ws?.sink.close();
    _ws = null;
  }

  Future<void> _poll() async {
    if (_state != DriverOperationalState.available) return;
    try {
      final assignment = await rideApi.getMyAssignment();
      await _handleAssignmentSeen(assignment);
    } on ApiException {
      // A single failed poll is not surfaced — the next tick retries.
    }
  }

  Future<void> _connectWs() async {
    try {
      final token = await apiClient.getAccessToken();
      if (token == null) return;
      final uri = apiClient.wsUri('/ws').replace(queryParameters: {'token': token});
      final ws = WebSocketChannel.connect(uri);
      // A bad host/refused connection surfaces as a rejected `ready`
      // future, not through the stream below — must be awaited here or it
      // becomes an unhandled async error instead of the silent,
      // polling-still-works fallback this method promises (see
      // user_app's RideSession, which hit exactly this in testing).
      await ws.ready;
      _ws = ws;
      ws.sink.add(jsonEncode({'type': 'subscribe_driver'}));
      _wsSub = ws.stream.listen(_onWsMessage, onError: (_) {}, cancelOnError: true);
    } catch (_) {
      // Best-effort only — polling above already fully drives assignment
      // discovery.
    }
  }

  void _onWsMessage(dynamic raw) {
    try {
      final msg = jsonDecode(raw as String) as Map<String, dynamic>;
      if (msg['type'] == 'driver:assignment' && msg['assignmentType'] == 'RIDE') {
        // The WS message itself carries no trip details — same "something
        // changed, go re-fetch" shape as trip:status on the rider side —
        // so trigger an immediate poll rather than trusting the message
        // payload for anything beyond "check now".
        unawaited(_poll());
      }
    } catch (_) {
      // A malformed/unrecognized WS message is ignored — polling remains
      // authoritative regardless.
    }
  }

  Future<void> _handleAssignmentSeen(Map<String, dynamic>? assignment) async {
    if (assignment == null) return;
    if (assignment['assignmentType'] != 'RIDE') return;
    final tripId = assignment['assignmentId'] as String?;
    if (tripId == null) return;
    if (tripId == _lastSeenAssignmentId) return; // already showing/handled this one
    try {
      final trip = await rideApi.getTrip(tripId);
      if (trip['status'] != 'MATCHED') return; // stale by the time we fetched it
      _lastSeenAssignmentId = tripId;
      _pendingRideAssignment = trip;
      notifyListeners();
    } on ApiException {
      // Couldn't fetch details this tick — leave unshown, next poll retries.
    }
  }

  /// Confirms the assignment still stands (re-fetches the trip — a stale
  /// notification, e.g. the rider having cancelled in the meantime, is
  /// caught here rather than trusted from the earlier poll/WS event), then
  /// marks the driver busy. Returns the confirmed trip on success.
  Future<Map<String, dynamic>?> acceptPendingRide() async {
    final pending = _pendingRideAssignment;
    if (pending == null || _assignmentActionInFlight) return null;
    final tripId = pending['id'] as String;
    _assignmentActionInFlight = true;
    notifyListeners();
    try {
      final trip = await rideApi.getTrip(tripId);
      if (trip['status'] != 'MATCHED') {
        // No longer valid (rider cancelled, or it moved on some other way)
        // — clear it honestly rather than opening a trip screen for a job
        // that no longer exists.
        _pendingRideAssignment = null;
        return null;
      }
      _pendingRideAssignment = null;
      markBusy(DriverOperationalState.onRide, tripId);
      return trip;
    } on ApiException {
      return null;
    } finally {
      _assignmentActionInFlight = false;
      notifyListeners();
    }
  }

  /// Declines a pending ride — the real backend transition (MATCHED ->
  /// CANCELLED) a driver is authorized to make on their own assigned trip,
  /// via the same PATCH /trips/:id/status endpoint the rest of the ride
  /// lifecycle uses. Returns whether it succeeded.
  Future<bool> declinePendingRide() async {
    final pending = _pendingRideAssignment;
    if (pending == null || _assignmentActionInFlight) return false;
    final tripId = pending['id'] as String;
    _assignmentActionInFlight = true;
    notifyListeners();
    try {
      await rideApi.updateStatus(tripId, 'CANCELLED');
      _pendingRideAssignment = null;
      return true;
    } on ApiException {
      // Already moved on (e.g. rider cancelled first, or it's no longer
      // MATCHED) — either way, nothing left for this driver to decline.
      _pendingRideAssignment = null;
      return false;
    } finally {
      _assignmentActionInFlight = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _stopAssignmentTracking();
    super.dispose();
  }
}
