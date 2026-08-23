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

/// Real matching has no "browse and accept" step for a driver — a trip is
/// matched synchronously and atomically server-side (services/matching.ts)
/// — so DriverSession's job is entirely: discover the match (poll/WS),
/// confirm it still stands, and drive the real PATCH .../status calls.
/// These tests cover that discovery/accept/decline flow without a real
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
        captured = request;
        return http.Response(jsonEncode({..._driverJson, 'online': true}), 200);
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

  group('assignment discovery + accept/decline', () {
    test('going online discovers a real matched trip via polling, surfaces it, then accept confirms + marks busy', () async {
      final tripJson = {
        'id': 'trip-1',
        'status': 'MATCHED',
        'pickup': 'A',
        'destination': 'B',
        'estimatedFare': 2500,
        'rider': {'firstName': 'Amaka', 'lastName': 'O'},
      };
      final session = _newSession(MockClient((request) async {
        if (request.url.path == '/api/drivers/me/assignment') {
          return http.Response(jsonEncode({'id': 'assign-1', 'assignmentType': 'RIDE', 'assignmentId': 'trip-1', 'status': 'ACTIVE'}), 200);
        }
        if (request.url.path == '/api/trips/trip-1') {
          return http.Response(jsonEncode(tripJson), 200);
        }
        if (request.url.path == '/api/drivers/me/online') {
          return http.Response(jsonEncode({..._driverJson, 'online': true}), 200);
        }
        return http.Response('{}', 200);
      }));

      final ok = await session.setOnline();
      expect(ok, isTrue);
      // setOnline() kicks off an unawaited poll — give it a tick to settle.
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(session.pendingRideAssignment?['id'], 'trip-1');

      final confirmed = await session.acceptPendingRide();

      expect(confirmed?['id'], 'trip-1');
      expect(session.pendingRideAssignment, isNull, reason: 'accepting clears the pending sheet state');
      expect(session.state, DriverOperationalState.onRide);
      expect(session.activeAssignmentId, 'trip-1');
    });

    test('acceptPendingRide() with no pending assignment is a safe no-op', () async {
      final session = _newSession(MockClient((_) async => http.Response('{}', 200)));

      final result = await session.acceptPendingRide();

      expect(result, isNull);
    });

    test('declinePendingRide() PATCHes the trip to CANCELLED and clears the pending sheet state', () async {
      final tripJson = {'id': 'trip-2', 'status': 'MATCHED', 'pickup': 'A', 'destination': 'B', 'estimatedFare': 1000};
      http.Request? declineRequest;
      final session = _newSession(MockClient((request) async {
        if (request.url.path == '/api/drivers/me/assignment') {
          return http.Response(jsonEncode({'id': 'assign-2', 'assignmentType': 'RIDE', 'assignmentId': 'trip-2', 'status': 'ACTIVE'}), 200);
        }
        if (request.url.path == '/api/trips/trip-2/status') {
          declineRequest = request;
          return http.Response(jsonEncode({...tripJson, 'status': 'CANCELLED'}), 200);
        }
        if (request.url.path == '/api/trips/trip-2') {
          return http.Response(jsonEncode(tripJson), 200);
        }
        if (request.url.path == '/api/drivers/me/online') {
          return http.Response(jsonEncode({..._driverJson, 'online': true}), 200);
        }
        return http.Response('{}', 200);
      }));

      await session.setOnline();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(session.pendingRideAssignment?['id'], 'trip-2');

      final ok = await session.declinePendingRide();

      expect(ok, isTrue);
      expect(jsonDecode(declineRequest!.body), {'status': 'CANCELLED'});
      expect(session.pendingRideAssignment, isNull);
      // Declining must never mark the driver busy — they stay available.
      expect(session.state, DriverOperationalState.available);
    });

    test('declinePendingRide() with no pending assignment is a safe no-op', () async {
      final session = _newSession(MockClient((_) async => http.Response('{}', 200)));

      final ok = await session.declinePendingRide();

      expect(ok, isFalse);
    });
  });

  group('reconcile', () {
    test('reconcile(busy:false) restarts assignment tracking only if the driver is online', () async {
      final session = _newSession(MockClient((_) async => http.Response(jsonEncode({..._driverJson, 'online': true}), 200)));
      await session.setOnline();
      session.markBusy(DriverOperationalState.onRide, 'trip-1');

      session.reconcile(busy: false);

      expect(session.state, DriverOperationalState.available);
      expect(session.activeAssignmentId, isNull);
    });
  });
}
