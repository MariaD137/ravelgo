import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ravelgo_rider_app/services/api/api_client.dart';
import 'package:ravelgo_rider_app/services/api/auth_provider.dart';
import 'package:ravelgo_rider_app/services/ride_session.dart';

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

RideSession _newSession(http.Client client) {
  final apiClient = ApiClient(authProvider: _FixedTokenProvider(), httpClient: client);
  RideSession.resetForTesting(authProvider: _FixedTokenProvider(), apiClient: apiClient);
  return RideSession.instance;
}

void main() {
  // RideSession is a singleton (RideSession.instance), same pattern as
  // driver_app's DriverSession — resetForTesting gives each test a clean
  // instance instead of leaking state (or a stale MockClient) between
  // tests.
  tearDown(() {
    RideSession.clearForTesting();
  });

  group('instance guard', () {
    test('reading instance before initialize()/resetForTesting() throws', () {
      RideSession.clearForTesting();
      expect(() => RideSession.instance, throwsA(isA<StateError>()));
    });
  });

  group('setRoute', () {
    test('derives a real distance/duration from both ends\' coordinates', () {
      final session = _newSession(MockClient((_) async => http.Response('{}', 200)));

      // Lekki Phase 1 -> Victoria Island, Lagos — roughly 9km apart.
      session.setRoute(
        pickup: 'Lekki Phase 1',
        destination: 'Victoria Island',
        pickupLat: 6.4400,
        pickupLng: 3.4600,
        destLat: 6.4300,
        destLng: 3.4200,
      );

      expect(session.distanceKm, isNotNull);
      expect(session.distanceKm, greaterThan(3));
      expect(session.distanceKm, lessThan(6));
      expect(session.durationMinutes, isNotNull);
      // durationMinutes is derived from distanceKm at a fixed 25km/h — not
      // an independent input — so it must track distanceKm exactly.
      expect(session.durationMinutes, closeTo(session.distanceKm! / 25 * 60, 0.001));
    });

    test('leaves distance/duration null when coordinates are missing', () {
      final session = _newSession(MockClient((_) async => http.Response('{}', 200)));

      session.setRoute(pickup: 'My Location', destination: 'Somewhere');

      expect(session.distanceKm, isNull);
      expect(session.durationMinutes, isNull);
    });

    test('clears a stale quote when the route changes', () {
      final session = _newSession(MockClient((_) async => http.Response('{}', 200)));
      session.quote = {'estimatedFare': 1500};

      session.setRoute(pickup: 'A', destination: 'B');

      expect(session.quote, isNull);
    });
  });

  group('fetchQuote', () {
    test('populates quote from GET /api/pricing/quote', () async {
      final session = _newSession(
        MockClient((request) async {
          expect(request.url.path, '/api/pricing/quote');
          return http.Response(jsonEncode({'estimatedFare': 2200, 'baseFare': 500}), 200);
        }),
      );
      session.setRoute(pickup: 'A', destination: 'B', pickupLat: 6.44, pickupLng: 3.46, destLat: 6.43, destLng: 3.42);

      await session.fetchQuote();

      expect(session.quote?['estimatedFare'], 2200);
      expect(session.quoteError, isNull);
    });

    test('sets quoteError instead of throwing when the backend has no active pricing rule', () async {
      final session = _newSession(
        MockClient((_) async => http.Response(jsonEncode({'error': 'No active pricing rule configured'}), 409)),
      );
      session.setRoute(pickup: 'A', destination: 'B', pickupLat: 6.44, pickupLng: 3.46, destLat: 6.43, destLng: 3.42);

      await session.fetchQuote();

      expect(session.quote, isNull);
      expect(session.quoteError, contains('pricing rule'));
    });

    test('refuses to quote without a selected route', () async {
      final session = _newSession(MockClient((_) async => http.Response('{}', 200)));

      await session.fetchQuote();

      expect(session.quoteError, isNotNull);
    });
  });

  group('requestTrip', () {
    test('on success, stores the trip and starts tracking (hasActiveTrip is true)', () async {
      final session = _newSession(
        MockClient((request) async {
          if (request.method == 'POST' && request.url.path == '/api/trips') {
            return http.Response(jsonEncode({'id': 'trip-1', 'status': 'REQUESTED'}), 201);
          }
          // The immediate post-request GET (to pick up driver info) — same
          // trip, still REQUESTED.
          return http.Response(jsonEncode({'id': 'trip-1', 'status': 'REQUESTED'}), 200);
        }),
      );
      session.setRoute(pickup: 'A', destination: 'B', pickupLat: 6.44, pickupLng: 3.46, destLat: 6.43, destLng: 3.42);

      final ok = await session.requestTrip();

      expect(ok, isTrue);
      expect(session.currentTrip?['id'], 'trip-1');
      expect(session.hasActiveTrip, isTrue);
      expect(session.requestError, isNull);
    });

    test('on a 409 (already has an open trip), surfaces the backend message and does not set a trip', () async {
      final session = _newSession(
        MockClient((_) async => http.Response(jsonEncode({'error': 'You already have an active trip request'}), 409)),
      );
      session.setRoute(pickup: 'A', destination: 'B', pickupLat: 6.44, pickupLng: 3.46, destLat: 6.43, destLng: 3.42);

      final ok = await session.requestTrip();

      expect(ok, isFalse);
      expect(session.currentTrip, isNull);
      expect(session.requestError, contains('already have an active trip'));
    });

    test('refuses to request without a selected route, without calling the backend', () async {
      var called = false;
      final session = _newSession(
        MockClient((_) async {
          called = true;
          return http.Response('{}', 201);
        }),
      );

      final ok = await session.requestTrip();

      expect(ok, isFalse);
      expect(called, isFalse);
    });

    test('a second concurrent call is refused while the first is still in flight (no duplicate POST)', () async {
      var postCount = 0;
      final session = _newSession(
        MockClient((request) async {
          if (request.method == 'POST') postCount++;
          return http.Response(jsonEncode({'id': 'trip-1', 'status': 'REQUESTED'}), 201);
        }),
      );
      session.setRoute(pickup: 'A', destination: 'B', pickupLat: 6.44, pickupLng: 3.46, destLat: 6.43, destLng: 3.42);

      final first = session.requestTrip();
      final second = session.requestTrip();

      expect(await second, isFalse);
      expect(await first, isTrue);
      expect(postCount, 1);
    });
  });

  group('cancelTrip', () {
    test('on success, updates currentTrip to the cancelled trip and stops tracking', () async {
      final session = _newSession(
        MockClient((request) async {
          if (request.method == 'POST') {
            return http.Response(jsonEncode({'id': 'trip-1', 'status': 'REQUESTED'}), 201);
          }
          if (request.method == 'PATCH') {
            return http.Response(jsonEncode({'id': 'trip-1', 'status': 'CANCELLED'}), 200);
          }
          return http.Response(jsonEncode({'id': 'trip-1', 'status': 'REQUESTED'}), 200);
        }),
      );
      session.setRoute(pickup: 'A', destination: 'B', pickupLat: 6.44, pickupLng: 3.46, destLat: 6.43, destLng: 3.42);
      await session.requestTrip();

      final ok = await session.cancelTrip();

      expect(ok, isTrue);
      expect(session.currentTrip?['status'], 'CANCELLED');
      expect(session.hasActiveTrip, isFalse);
    });

    test('with no current trip, does nothing and returns false', () async {
      final session = _newSession(MockClient((_) async => http.Response('{}', 200)));

      final ok = await session.cancelTrip();

      expect(ok, isFalse);
    });
  });

  group('clearTrip', () {
    test('resets route selection, quote, and trip state', () async {
      final session = _newSession(
        MockClient((_) async => http.Response(jsonEncode({'id': 'trip-1', 'status': 'REQUESTED'}), 201)),
      );
      session.setRoute(pickup: 'A', destination: 'B', pickupLat: 6.44, pickupLng: 3.46, destLat: 6.43, destLng: 3.42);
      await session.requestTrip();

      session.clearTrip();

      expect(session.currentTrip, isNull);
      expect(session.pickup, isNull);
      expect(session.destination, isNull);
      expect(session.distanceKm, isNull);
      expect(session.hasActiveTrip, isFalse);
    });
  });
}
