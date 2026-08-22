import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ravelgo_rider_app/services/api/api_client.dart';
import 'package:ravelgo_rider_app/services/api/auth_provider.dart';
import 'package:ravelgo_rider_app/services/api/ride_api.dart';

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

void main() {
  test('requestTrip() posts pickup/destination/distance/duration and returns the created trip', () async {
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response(jsonEncode({'id': 'trip-1', 'status': 'REQUESTED'}), 201);
    });
    final api = RideApi(ApiClient(authProvider: _FixedTokenProvider(), httpClient: client));

    final result = await api.requestTrip(
      pickup: 'Lekki Phase 1',
      destination: 'Victoria Island',
      distanceKm: 8.2,
      durationMinutes: 18,
    );

    expect(captured.url.path, '/api/trips');
    final body = jsonDecode(captured.body) as Map<String, dynamic>;
    expect(body['pickup'], 'Lekki Phase 1');
    expect(body['destination'], 'Victoria Island');
    expect(body['distanceKm'], 8.2);
    expect(body['durationMinutes'], 18);
    expect(body.containsKey('estimatedFare'), isFalse);
    expect(result['id'], 'trip-1');
  });

  test('getTrip() fetches a trip by id', () async {
    final client = MockClient(
      (request) async => http.Response(jsonEncode({'id': 'trip-1', 'status': 'IN_PROGRESS'}), 200),
    );
    final api = RideApi(ApiClient(authProvider: _FixedTokenProvider(), httpClient: client));

    final result = await api.getTrip('trip-1');

    expect(result['status'], 'IN_PROGRESS');
  });

  test('cancelTrip() 409s with the backend message when the trip is no longer cancellable', () async {
    final client = MockClient(
      (request) async => http.Response(jsonEncode({'error': 'Trip cannot be cancelled from status COMPLETED'}), 409),
    );
    final api = RideApi(ApiClient(authProvider: _FixedTokenProvider(), httpClient: client));

    await expectLater(
      api.cancelTrip('trip-1'),
      throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 409)),
    );
  });

  test('myTrips() unwraps the paginated {data, total} envelope into a list', () async {
    final client = MockClient(
      (request) async => http.Response(
        jsonEncode({
          'data': [
            {'id': 'trip-2'},
            {'id': 'trip-1'},
          ],
          'total': 2,
          'page': 1,
          'pageSize': 20,
        }),
        200,
      ),
    );
    final api = RideApi(ApiClient(authProvider: _FixedTokenProvider(), httpClient: client));

    final result = await api.myTrips();

    expect(result.map((t) => t['id']), ['trip-2', 'trip-1']);
  });
}
