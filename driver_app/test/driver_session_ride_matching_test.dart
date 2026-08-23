import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ravelgo_driver_app/models/driver_operational_state.dart';
import 'package:ravelgo_driver_app/services/api/api_client.dart';
import 'package:ravelgo_driver_app/services/api/auth_provider.dart';
import 'package:ravelgo_driver_app/services/driver_session.dart';

class _FixedTokenProvider implements AuthProvider {
  @override
  Future<String?> getAccessToken() async => 'tok';
  @override
  Future<bool> isAuthenticated() async => true;
  @override
  Future<void> login({required String username, required String password}) async =>
      throw UnimplementedError();
  @override
  Future<void> logout() async => throw UnimplementedError();
}

DriverSession _newSession(http.Client client) {
  final apiClient = ApiClient(authProvider: _FixedTokenProvider(), httpClient: client);
  DriverSession.resetForTesting(authProvider: _FixedTokenProvider(), apiClient: apiClient);
  return DriverSession.instance;
}

const _driverJson = {
  'id': 'driver-1',
  'rating': 4.7,
  'totalTrips': 42,
  'preferredLanguage': 'English',
  'quietModePreferred': false,
  'online': false,
  'user': {'firstName': 'Femi', 'lastName': 'Balogun', 'email': 'femi@example.com', 'phoneNumber': '+1555'},
};

/// Real dispatch is a genuine offer/accept flow, not a synchronous
/// auto-match: the backend offers a REQUESTED trip to one eligible driver
/// at a time (services/matching.ts), and this driver must explicitly
/// ACCEPT or DECLINE — there is no automatic acceptance anywhere in this
/// class. These tests cover discovery (GET /api/drivers/me/offer),
/// accept (PATCH /api/trip-offers/:id/accept), decline (PATCH
/// /api/trip-offers/:id/decline), and the one-time "already committed job"
/// reconciliation (GET /api/drivers/me/assignment) — without a real
/// backend, matching the same MockClient pattern used for user_app's
/// RideSession.
void main() {
  tearDown(() {
    DriverSession.clearForTesting();
  });

  group('loadProfile', () {
    test('populates a real DriverProfile from GET /api/drivers/me', () async {
      final session = _newSession(MockClient((request) async {
        expect(request.url.path, '/api/drivers/me');
        return http.Response(jsonEncode(_driverJson), 200);
      }));

      final ok = await session.loadProfile();

      expect(ok, isTrue);
      expect(session.profile?.firstName, 'Femi');
      expect(session.profile?.rating, 4.7);
    });

    test('returns false (no fabricated profile) on a 404 — no Driver row yet', () async {
      final session = _newSession(MockClient((_) async => http.Response(jsonEncode({'error': 'not found'}), 404)));

      final ok = await session.loadProfile();

      expect(ok, isFalse);
      expect(session.profile, isNull);
    });
  });

  group('setOnline / setOffline', () {
    test('setOnline() PATCHes online:true and goes available on success', () async {
      late http.Request captured;
      final session = _newSession(MockClient((request) async {
        if (request.url.path == '/api/drivers/me/online') captured = request;
        if (request.url.path == '/api/drivers/me/online') {
          return http.Response(jsonEncode({..._driverJson, 'online': true}), 200);
        }
        return http.Response('null', 200);
      }));

      final ok = await session.setOnline();

      expect(ok, isTrue);
      expect(captured.url.path, '/api/drivers/me/online');
      expect(jsonDecode(captured.body), {'online': true});
      expect(session.state, DriverOperationalState.available);
      expect(session.profile?.isOnline, isTrue);
    });

    test('setOnline() failure leaves state unchanged and returns false', () async {
      final session = _newSession(MockClient((_) async => http.Response(jsonEncode({'error': 'nope'}), 404)));

      final ok = await session.setOnline();

      expect(ok, isFalse);
      expect(session.state, DriverOperationalState.offline);
    });

    test('setOffline() while busy on a ride does not clear the busy state', () async {
      final session = _newSession(MockClient((request) async => http.Response(jsonEncode({..._driverJson, 'online': false}), 200)));
      session.markBusy(DriverOperationalState.onRide, 'trip-1');

      final ok = await session.setOffline();

      expect(ok, isTrue);
      expect(session.state, DriverOperationalState.onRide, reason: 'going offline must never interrupt an active job');
    });
  });

  group('offer discovery + accept/decline', () {
    test('going online discovers a real pending offer via polling, surfaces it, then accept confirms + marks busy', () async {
      final tripJson = {
        'id': 'trip-1',
        'status': 'REQUESTED',
        'pickup': 'A',
        'destination': 'B',
        'estimatedFare': 2500,
        'rider': {'firstName': 'Amaka', 'lastName': 'O'},
      };
      http.Request? acceptRequest;
      final session = _newSession(MockClient((request) async {
        if (request.url.path == '/api/drivers/me/assignment') {
          return http.Response('null', 200); // nothing already committed
        }
        if (request.url.path == '/api/drivers/me/offer') {
          return http.Response(
            jsonEncode({'id': 'offer-1', 'tripId': 'trip-1', 'status': 'OFFERED', 'expiresAt': '2099-01-01T00:00:00.000Z'}),
            200,
          );
        }
        if (request.url.path == '/api/trips/trip-1') {
          return http.Response(jsonEncode(tripJson), 200);
        }
        if (request.url.path == '/api/trip-offers/offer-1/accept') {
          acceptRequest = request;
          return http.Response(jsonEncode({...tripJson, 'status': 'MATCHED', 'driverId': 'driver-1'}), 200);
        }
        if (request.url.path == '/api/drivers/me/online') {
          return http.Response(jsonEncode({..._driverJson, 'online': true}), 200);
        }
        return http.Response('null', 200);
      }));

      final ok = await session.setOnline();
      expect(ok, isTrue);
      // setOnline() kicks off unawaited reconciliation + polling — give it
      // a tick to settle.
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(session.pendingRideOffer?['id'], 'trip-1');
      expect(session.pendingRideOffer?['offerId'], 'offer-1');

      final confirmed = await session.acceptPendingRide();

      expect(acceptRequest?.method, 'PATCH');
      expect(confirmed?['id'], 'trip-1');
      expect(confirmed?['status'], 'MATCHED');
      expect(session.pendingRideOffer, isNull, reason: 'accepting clears the pending sheet state');
      expect(session.state, DriverOperationalState.onRide);
      expect(session.activeAssignmentId, 'trip-1');
    });

    test('acceptPendingRide() with no pending offer is a safe no-op', () async {
      final session = _newSession(MockClient((_) async => http.Response('null', 200)));

      final result = await session.acceptPendingRide();

      expect(result, isNull);
    });

    test('a losing accept (offer already resolved elsewhere) clears the pending offer without marking busy', () async {
      final tripJson = {'id': 'trip-1', 'status': 'REQUESTED', 'pickup': 'A', 'destination': 'B', 'estimatedFare': 2500};
      final session = _newSession(MockClient((request) async {
        if (request.url.path == '/api/drivers/me/assignment') return http.Response('null', 200);
        if (request.url.path == '/api/drivers/me/offer') {
          return http.Response(jsonEncode({'id': 'offer-1', 'tripId': 'trip-1', 'status': 'OFFERED', 'expiresAt': '2099-01-01T00:00:00.000Z'}), 200);
        }
        if (request.url.path == '/api/trips/trip-1') return http.Response(jsonEncode(tripJson), 200);
        if (request.url.path == '/api/trip-offers/offer-1/accept') {
          return http.Response(jsonEncode({'error': 'offer no longer available'}), 409);
        }
        if (request.url.path == '/api/drivers/me/online') return http.Response(jsonEncode({..._driverJson, 'online': true}), 200);
        return http.Response('null', 200);
      }));

      await session.setOnline();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(session.pendingRideOffer?['id'], 'trip-1');

      final confirmed = await session.acceptPendingRide();

      expect(confirmed, isNull);
      expect(session.pendingRideOffer, isNull);
      expect(session.state, DriverOperationalState.available, reason: 'a losing accept must never mark the driver busy');
    });

    test('declinePendingRide() PATCHes the offer to declined — never the trip itself', () async {
      final tripJson = {'id': 'trip-2', 'status': 'REQUESTED', 'pickup': 'A', 'destination': 'B', 'estimatedFare': 1000};
      http.Request? declineRequest;
      final session = _newSession(MockClient((request) async {
        if (request.url.path == '/api/drivers/me/assignment') return http.Response('null', 200);
        if (request.url.path == '/api/drivers/me/offer') {
          return http.Response(jsonEncode({'id': 'offer-2', 'tripId': 'trip-2', 'status': 'OFFERED', 'expiresAt': '2099-01-01T00:00:00.000Z'}), 200);
        }
        if (request.url.path == '/api/trip-offers/offer-2/decline') {
          declineRequest = request;
          return http.Response(jsonEncode({'id': 'offer-2', 'status': 'DECLINED'}), 200);
        }
        if (request.url.path == '/api/trips/trip-2') {
          return http.Response(jsonEncode(tripJson), 200);
        }
        if (request.url.path == '/api/drivers/me/online') {
          return http.Response(jsonEncode({..._driverJson, 'online': true}), 200);
        }
        return http.Response('null', 200);
      }));

      await session.setOnline();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(session.pendingRideOffer?['id'], 'trip-2');

      final ok = await session.declinePendingRide();

      expect(ok, isTrue);
      expect(declineRequest?.method, 'PATCH');
      expect(declineRequest?.url.path, '/api/trip-offers/offer-2/decline');
      expect(session.pendingRideOffer, isNull);
      // Declining must never mark the driver busy, and must never touch
      // the trip's own status — they stay available for the next offer.
      expect(session.state, DriverOperationalState.available);
    });

    test('declinePendingRide() with no pending offer is a safe no-op', () async {
      final session = _newSession(MockClient((_) async => http.Response('null', 200)));

      final ok = await session.declinePendingRide();

      expect(ok, isFalse);
    });

    test('clearPendingOfferOnLocalTimeout() hides the sheet without calling decline', () async {
      final tripJson = {'id': 'trip-3', 'status': 'REQUESTED', 'pickup': 'A', 'destination': 'B', 'estimatedFare': 500};
      bool declineCalled = false;
      final session = _newSession(MockClient((request) async {
        if (request.url.path == '/api/drivers/me/assignment') return http.Response('null', 200);
        if (request.url.path == '/api/drivers/me/offer') {
          return http.Response(jsonEncode({'id': 'offer-3', 'tripId': 'trip-3', 'status': 'OFFERED', 'expiresAt': '2099-01-01T00:00:00.000Z'}), 200);
        }
        if (request.url.path == '/api/trips/trip-3') return http.Response(jsonEncode(tripJson), 200);
        if (request.url.path == '/api/trip-offers/offer-3/decline') {
          declineCalled = true;
          return http.Response('{}', 200);
        }
        if (request.url.path == '/api/drivers/me/online') return http.Response(jsonEncode({..._driverJson, 'online': true}), 200);
        return http.Response('null', 200);
      }));

      await session.setOnline();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(session.pendingRideOffer?['id'], 'trip-3');

      session.clearPendingOfferOnLocalTimeout();

      expect(session.pendingRideOffer, isNull);
      expect(declineCalled, isFalse, reason: 'a local timeout must never record a real decline');
    });

    test('an already-committed job (assignment) found on tracking start marks the driver busy directly, without an offer sheet', () async {
      final session = _newSession(MockClient((request) async {
        if (request.url.path == '/api/drivers/me/assignment') {
          return http.Response(jsonEncode({'id': 'assign-1', 'assignmentType': 'RIDE', 'assignmentId': 'trip-4', 'status': 'ACTIVE'}), 200);
        }
        if (request.url.path == '/api/drivers/me/online') {
          return http.Response(jsonEncode({..._driverJson, 'online': true}), 200);
        }
        return http.Response('null', 200);
      }));

      await session.setOnline();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(session.state, DriverOperationalState.onRide);
      expect(session.activeAssignmentId, 'trip-4');
      expect(session.pendingRideOffer, isNull);
    });
  });

  group('reconcile', () {
    test('reconcile(busy:false) restarts offer tracking only if the driver is online', () async {
      final session = _newSession(MockClient((_) async => http.Response(jsonEncode({..._driverJson, 'online': true}), 200)));
      await session.setOnline();
      session.markBusy(DriverOperationalState.onRide, 'trip-1');

      session.reconcile(busy: false);

      expect(session.state, DriverOperationalState.available);
      expect(session.activeAssignmentId, isNull);
    });
  });
}
