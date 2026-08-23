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
/// Ride matching is a real Uber-style offer/accept flow: the backend offers
/// a REQUESTED trip to one eligible driver at a time (services/matching.ts)
/// — the driver sees a real "new ride request" and chooses ACCEPT or
/// DECLINE, never an automatic acceptance. This class's polling loop and
/// best-effort WebSocket connection are how a driver discovers a pending
/// offer at all, not a client-side matching engine — every decision (who
/// gets offered what, whether an accept wins a concurrency race) is made
/// and enforced by the backend; this class only asks it and mirrors the
/// answer. Declining an offer never affects the driver's own account
/// status (Driver.status is a separate, one-time admin-approval state
/// machine) — the driver stays available for the next offer.
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

  /// Trip JSON for a real pending ride offer (merged with `offerId` and
  /// `offerExpiresAt`), discovered via polling/WS and not yet acted on
  /// (accepted or declined). Null the rest of the time. Driver-facing
  /// screens (driver_home_screen.dart) show the incoming-request sheet
  /// exactly when this is non-null — never on a local timer or a
  /// "simulate" button.
  Map<String, dynamic>? _pendingRideOffer;
  Map<String, dynamic>? get pendingRideOffer => _pendingRideOffer;

  bool _assignmentActionInFlight = false;
  bool get assignmentActionInFlight => _assignmentActionInFlight;

  Timer? _pollTimer;
  WebSocketChannel? _ws;
  StreamSubscription? _wsSub;
  String? _lastSeenOfferId;

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
    _pendingRideOffer = null;
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
        // Resume offer discovery — needed after an app restart, where this
        // is the first signal that the driver was left online.
        _startAssignmentTracking();
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

  // --- Ride offer discovery (polling primary + WS overlay) -----------------

  void _startAssignmentTracking() {
    _pollTimer?.cancel();
    // Polling is the primary, always-correct mechanism — a new offer
    // requires no client push to be discoverable at all; the WebSocket
    // connection below is a best-effort latency improvement on top of it,
    // never a replacement for it.
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) => _poll());
    // One-time reconciliation for a job already committed before this
    // tracking session started (e.g. the app was restarted mid-ride) —
    // a normal accept already marks the driver busy directly and stops
    // tracking, so this only catches state that predates it.
    unawaited(_reconcileExistingAssignment());
    unawaited(_connectWs());
  }

  Future<void> _reconcileExistingAssignment() async {
    try {
      final assignment = await rideApi.getMyAssignment();
      if (assignment != null && assignment['assignmentType'] == 'RIDE') {
        reconcile(busy: true, assignmentType: 'RIDE', assignmentId: assignment['assignmentId'] as String?);
        return;
      }
    } on ApiException {
      // Fall through — the regular poll loop below will still discover
      // any pending offer.
    }
    unawaited(_poll());
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
      final offer = await rideApi.getMyOffer();
      await _handleOfferSeen(offer);
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
      if (msg['type'] == 'driver:offer') {
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

  Future<void> _handleOfferSeen(Map<String, dynamic>? offer) async {
    if (offer == null) return;
    final offerId = offer['id'] as String?;
    final tripId = offer['tripId'] as String?;
    if (offerId == null || tripId == null) return;
    if (offerId == _lastSeenOfferId) return; // already showing/handled this one
    try {
      final trip = await rideApi.getTrip(tripId);
      if (trip['status'] != 'REQUESTED') return; // stale by the time we fetched it
      _lastSeenOfferId = offerId;
      _pendingRideOffer = {...trip, 'offerId': offerId, 'offerExpiresAt': offer['expiresAt']};
      notifyListeners();
    } on ApiException {
      // Couldn't fetch details this tick — leave unshown, next poll retries.
    }
  }

  /// Accepts the real pending offer — PATCH /trip-offers/:id/accept.
  /// Atomic and concurrency-safe server-side: a losing race against
  /// another driver's accept, or an offer that already expired, surfaces
  /// as an [ApiException] here rather than a fabricated success. Marks the
  /// driver busy and returns the now-MATCHED trip only on genuine success.
  Future<Map<String, dynamic>?> acceptPendingRide() async {
    final pending = _pendingRideOffer;
    if (pending == null || _assignmentActionInFlight) return null;
    final offerId = pending['offerId'] as String;
    _assignmentActionInFlight = true;
    notifyListeners();
    try {
      final trip = await rideApi.acceptOffer(offerId);
      _pendingRideOffer = null;
      markBusy(DriverOperationalState.onRide, trip['id'] as String);
      return trip;
    } on ApiException {
      // No longer available (already expired, already resolved, or lost a
      // concurrent accept race to another driver) — clear it honestly
      // rather than opening a trip screen for a job that never became
      // this driver's.
      _pendingRideOffer = null;
      return null;
    } finally {
      _assignmentActionInFlight = false;
      notifyListeners();
    }
  }

  /// Declines a pending offer — PATCH /trip-offers/:id/decline. This only
  /// resolves this one offer for this one driver: it never cancels the
  /// rider's trip (the backend offers it on to the next eligible driver)
  /// and never touches this driver's own account status or availability —
  /// the driver stays ACTIVE, ONLINE, and eligible for the next offer.
  /// Returns whether it succeeded.
  Future<bool> declinePendingRide() async {
    final pending = _pendingRideOffer;
    if (pending == null || _assignmentActionInFlight) return false;
    final offerId = pending['offerId'] as String;
    _assignmentActionInFlight = true;
    notifyListeners();
    try {
      await rideApi.declineOffer(offerId);
      _pendingRideOffer = null;
      return true;
    } on ApiException {
      // Already resolved some other way (e.g. it expired first) — either
      // way, nothing left for this driver to decline.
      _pendingRideOffer = null;
      return false;
    } finally {
      _assignmentActionInFlight = false;
      notifyListeners();
    }
  }

  /// Called only when the incoming-request sheet's own countdown reaches
  /// zero — hides the sheet locally without recording anything. This must
  /// never call [declinePendingRide]: a local timeout is not a driver
  /// decision, and recording it as a DECLINE would corrupt the driver's
  /// acceptance-rate stats. The backend's own lazy expiration (checked on
  /// the next offer/trip poll, by whichever side reads it first) is what
  /// actually records EXPIRED.
  void clearPendingOfferOnLocalTimeout() {
    if (_pendingRideOffer == null) return;
    _pendingRideOffer = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _stopAssignmentTracking();
    super.dispose();
  }
}
