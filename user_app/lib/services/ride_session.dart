import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'api/api_client.dart';
import 'api/auth_provider.dart';
import 'api/pricing_api.dart';
import 'api/ride_api.dart';

/// The app-wide holder of the rider's in-progress ride request/trip and the
/// domain API clients the ride-flow screens use to reach the backend.
/// Mirrors driver_app's `DriverSession` (see that file's doc comment for
/// why a single ChangeNotifier singleton rather than a state-management
/// package): one shared instance (`RideSession.instance`), set up once from
/// main.dart's composition root via [initialize] with an explicit
/// [AuthProvider], never constructed implicitly by a screen.
///
/// Trip status here is always what the backend last confirmed — via a poll
/// response or a `trip:status` WebSocket message — never a locally-assumed
/// transition. A tap on "Request ride" does not set status to MATCHED
/// itself; only a server response does.
class RideSession extends ChangeNotifier {
  RideSession({required AuthProvider authProvider, required ApiClient apiClient})
    : _authProvider = authProvider,
      apiClient = apiClient,
      rideApi = RideApi(apiClient),
      pricingApi = PricingApi(apiClient);

  static RideSession? _instance;

  static RideSession get instance {
    final session = _instance;
    if (session == null) {
      throw StateError(
        'RideSession.instance was read before RideSession.initialize() ran. '
        'Call RideSession.initialize(...) from main() before runApp().',
      );
    }
    return session;
  }

  /// The app's composition root (main.dart) calls this exactly once, with
  /// an [AuthProvider] chosen there — see driver_app's DriverSession for
  /// why this must never default to a dev-only provider itself.
  static void initialize({required AuthProvider authProvider, required ApiClient apiClient}) {
    _instance = RideSession(authProvider: authProvider, apiClient: apiClient);
  }

  @visibleForTesting
  static void resetForTesting({required AuthProvider authProvider, required ApiClient apiClient}) {
    _instance?._stopTracking();
    _instance = RideSession(authProvider: authProvider, apiClient: apiClient);
  }

  @visibleForTesting
  static void clearForTesting() {
    _instance?._stopTracking();
    _instance = null;
  }

  // ignore: unused_field
  final AuthProvider _authProvider;
  final ApiClient apiClient;
  final RideApi rideApi;
  final PricingApi pricingApi;

  static const _terminalStatuses = {'COMPLETED', 'CANCELLED', 'DISPUTED'};
  static bool _isTerminal(String? status) => _terminalStatuses.contains(status);

  // --- Route selection (FindRoute -> SelectRide) ---------------------------

  String? pickup;
  String? destination;
  double? pickupLat;
  double? pickupLng;
  double? destLat;
  double? destLng;
  double? distanceKm;
  double? durationMinutes;

  /// Sets the rider's chosen pickup/destination. When both ends' coordinates
  /// are known (from the Places search result the rider tapped), also
  /// derives a straight-line [distanceKm] and an average-speed
  /// [durationMinutes] estimate — real values computed from the rider's
  /// actual selection, not a hardcoded fare. This is a straight-line
  /// approximation, not a routed distance (no Directions API call is wired
  /// up); the backend's own PricingRule still produces the real quote/fare
  /// from whatever distance/duration it is given.
  void setRoute({
    required String pickup,
    required String destination,
    double? pickupLat,
    double? pickupLng,
    double? destLat,
    double? destLng,
  }) {
    this.pickup = pickup;
    this.destination = destination;
    this.pickupLat = pickupLat;
    this.pickupLng = pickupLng;
    this.destLat = destLat;
    this.destLng = destLng;
    quote = null;
    quoteError = null;
    if (pickupLat != null && pickupLng != null && destLat != null && destLng != null) {
      distanceKm = _haversineKm(pickupLat, pickupLng, destLat, destLng);
      // No routing/traffic data is available locally — 25 km/h is a
      // deliberately conservative average-urban-speed assumption used only
      // to turn a real distance into a real duration estimate for the
      // backend's per-minute pricing term; it is not presented to the
      // rider as a routed ETA.
      durationMinutes = (distanceKm! / 25) * 60;
    } else {
      distanceKm = null;
      durationMinutes = null;
    }
    notifyListeners();
  }

  static double _haversineKm(double lat1, double lon1, double lat2, double lon2) {
    const earthRadiusKm = 6371.0;
    final dLat = _degToRad(lat2 - lat1);
    final dLon = _degToRad(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_degToRad(lat1)) * math.cos(_degToRad(lat2)) * math.sin(dLon / 2) * math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusKm * c;
  }

  static double _degToRad(double deg) => deg * math.pi / 180;

  // --- Pricing quote --------------------------------------------------------

  Map<String, dynamic>? quote;
  String? quoteError;
  bool quoteLoading = false;

  Future<void> fetchQuote() async {
    if (distanceKm == null || durationMinutes == null) {
      quoteError = 'Select a pickup and a destination first.';
      notifyListeners();
      return;
    }
    quoteLoading = true;
    quoteError = null;
    notifyListeners();
    try {
      quote = await pricingApi.getQuote(distanceKm: distanceKm!, durationMinutes: durationMinutes!);
    } on ApiException catch (e) {
      quoteError = e.message;
    } finally {
      quoteLoading = false;
      notifyListeners();
    }
  }

  // --- Trip request + live tracking -----------------------------------------

  Map<String, dynamic>? currentTrip;
  String? requestError;
  bool requesting = false;
  Map<String, dynamic>? driverLocation;

  bool get hasActiveTrip => currentTrip != null && !_isTerminal(currentTrip!['status'] as String?);

  Timer? _pollTimer;
  WebSocketChannel? _ws;
  StreamSubscription? _wsSub;

  /// Requests a trip from the real backend. Guarded by [requesting] so a
  /// double tap on "Request ride" (or a slow first response) can never fire
  /// a second POST /trips — the backend itself also rejects a second open
  /// trip per rider with 409, but this stops the duplicate request from
  /// ever leaving the client.
  Future<bool> requestTrip({String? pickupNote}) async {
    if (requesting) return false;
    if (pickup == null || destination == null) {
      requestError = 'Select a pickup and a destination first.';
      notifyListeners();
      return false;
    }
    requesting = true;
    requestError = null;
    notifyListeners();
    try {
      final trip = await rideApi.requestTrip(
        pickup: pickup!,
        destination: destination!,
        distanceKm: distanceKm,
        durationMinutes: durationMinutes,
        pickupNote: pickupNote,
        estimatedFare: (quote?['estimatedFare'] as num?)?.toDouble(),
      );
      currentTrip = trip;
      final tripId = trip['id'] as String?;
      if (tripId != null) {
        _startTracking(tripId);
        // matchDriverToTrip's response (if matched inline) carries no
        // nested driver/user relation — fetch the full trip once right
        // away so the UI can show driver info without waiting for the
        // first poll tick.
        unawaited(_poll(tripId));
      }
      return true;
    } on ApiException catch (e) {
      requestError = e.message;
      return false;
    } finally {
      requesting = false;
      notifyListeners();
    }
  }

  void _startTracking(String tripId) {
    _pollTimer?.cancel();
    // Polling is the robust, always-available primary mechanism per
    // docs/realtime-architecture.md ("every REST endpoint has an HTTP
    // polling equivalent") — the trip reaches every state through this
    // alone even if the WebSocket below never connects.
    _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) => _poll(tripId));
    unawaited(_connectWs(tripId));
  }

  Future<void> _poll(String tripId) async {
    try {
      final trip = await rideApi.getTrip(tripId);
      currentTrip = trip;
      notifyListeners();
      if (_isTerminal(trip['status'] as String?)) {
        _stopTracking();
      }
    } on ApiException {
      // A single failed poll must not surface as a user-facing error —
      // polling is the primary channel precisely because it retries every
      // tick; the next tick recovers from a transient failure on its own.
    }
  }

  Future<void> _connectWs(String tripId) async {
    try {
      final token = await apiClient.getAccessToken();
      if (token == null) return;
      final uri = apiClient.wsUri('/ws').replace(queryParameters: {'token': token});
      final ws = WebSocketChannel.connect(uri);
      // A bad host/URI or a refused connection surfaces here, as a
      // rejected Future — not through the stream below — so it must be
      // awaited inside this try block. Left un-awaited, the same failure
      // becomes an unhandled async error instead of the silent,
      // polling-still-works fallback this method promises.
      await ws.ready;
      _ws = ws;
      ws.sink.add(jsonEncode({'type': 'subscribe', 'tripId': tripId}));
      _wsSub = ws.stream.listen(
        _onWsMessage,
        onError: (_) {
          // Best-effort only — polling above already fully drives trip
          // tracking, so a WS-level error is silently dropped rather than
          // surfaced to the rider.
        },
        cancelOnError: true,
      );
    } catch (_) {
      // Connect failure (no network, backend WS unreachable, etc.) — never
      // breaks the flow; polling alone still tracks the trip to completion.
    }
  }

  void _onWsMessage(dynamic raw) {
    try {
      final msg = jsonDecode(raw as String) as Map<String, dynamic>;
      final trip = currentTrip;
      if (trip == null) return;
      switch (msg['type']) {
        case 'trip:status':
          if (msg['tripId'] == trip['id']) {
            currentTrip = {
              ...trip,
              'status': msg['status'],
              if (msg['finalFare'] != null) 'finalFare': msg['finalFare'],
            };
            notifyListeners();
            if (_isTerminal(msg['status'] as String?)) _stopTracking();
          }
          break;
        case 'location':
          driverLocation = msg;
          notifyListeners();
          break;
      }
    } catch (_) {
      // A malformed/unrecognized WS message is ignored — polling remains
      // the source of truth regardless.
    }
  }

  void _stopTracking() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _wsSub?.cancel();
    _wsSub = null;
    _ws?.sink.close();
    _ws = null;
  }

  /// Re-fetches the current trip on demand (e.g. pull-to-refresh on the
  /// status screen), independent of the polling timer's own cadence.
  Future<void> refreshTrip() async {
    final tripId = currentTrip?['id'] as String?;
    if (tripId == null) return;
    await _poll(tripId);
  }

  Future<bool> cancelTrip() async {
    final tripId = currentTrip?['id'] as String?;
    if (tripId == null) return false;
    try {
      final updated = await rideApi.cancelTrip(tripId);
      currentTrip = updated;
      _stopTracking();
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      requestError = e.message;
      notifyListeners();
      return false;
    }
  }

  /// Resets route selection and trip state, e.g. once a completed/cancelled
  /// trip has been shown to the rider and they return to the home screen.
  void clearTrip() {
    _stopTracking();
    currentTrip = null;
    driverLocation = null;
    pickup = null;
    destination = null;
    pickupLat = pickupLng = destLat = destLng = null;
    distanceKm = null;
    durationMinutes = null;
    quote = null;
    quoteError = null;
    requestError = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _stopTracking();
    super.dispose();
  }
}
