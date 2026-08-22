import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ravelgo_rider_app/services/api/api_client.dart';
import 'package:ravelgo_rider_app/services/api/auth_provider.dart';
import 'package:ravelgo_rider_app/services/api/rental_api.dart';

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
  test('browseListings() unwraps the paginated {data, total} envelope into a list', () async {
    final client = MockClient(
      (request) async => http.Response(
        jsonEncode({
          'data': [
            {'id': 'rl-1', 'status': 'APPROVED'},
          ],
          'total': 1,
          'page': 1,
          'pageSize': 20,
        }),
        200,
      ),
    );
    final api = RentalApi(ApiClient(authProvider: _FixedTokenProvider(), httpClient: client));

    final result = await api.browseListings();

    expect(result.map((l) => l['id']), ['rl-1']);
  });

  test('createBooking() posts ISO-8601 start/end and returns the created booking', () async {
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response(jsonEncode({'id': 'rb-1', 'status': 'REQUESTED'}), 201);
    });
    final api = RentalApi(ApiClient(authProvider: _FixedTokenProvider(), httpClient: client));

    final start = DateTime.utc(2026, 9, 1);
    final end = DateTime.utc(2026, 9, 3);
    final result = await api.createBooking(rentalListingId: 'rl-1', startAt: start, endAt: end);

    expect(captured.url.path, '/api/rentals/rl-1/bookings');
    final body = jsonDecode(captured.body) as Map<String, dynamic>;
    expect(body['startAt'], start.toIso8601String());
    expect(body['endAt'], end.toIso8601String());
    expect(result['id'], 'rb-1');
  });

  test('createBooking() surfaces a RENTAL_OVERLAP 409 as ApiException', () async {
    final client = MockClient(
      (request) async => http.Response(
        jsonEncode({'code': 'RENTAL_OVERLAP', 'message': 'This listing is already booked for that range'}),
        409,
      ),
    );
    final api = RentalApi(ApiClient(authProvider: _FixedTokenProvider(), httpClient: client));

    await expectLater(
      api.createBooking(
        rentalListingId: 'rl-1',
        startAt: DateTime.utc(2026, 9, 1),
        endAt: DateTime.utc(2026, 9, 3),
      ),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', 'RENTAL_OVERLAP')),
    );
  });

  test('myBookings() returns the plain list the backend sends (unpaginated)', () async {
    final client = MockClient(
      (request) async => http.Response(
        jsonEncode([
          {'id': 'rb-1'},
          {'id': 'rb-2'},
        ]),
        200,
      ),
    );
    final api = RentalApi(ApiClient(authProvider: _FixedTokenProvider(), httpClient: client));

    final result = await api.myBookings();

    expect(result.map((b) => b['id']), ['rb-1', 'rb-2']);
  });

  test('cancelBooking() 409s with the backend message when no longer cancellable', () async {
    final client = MockClient(
      (request) async => http.Response(jsonEncode({'error': 'Booking cannot be cancelled from status ACTIVE'}), 409),
    );
    final api = RentalApi(ApiClient(authProvider: _FixedTokenProvider(), httpClient: client));

    await expectLater(
      api.cancelBooking('rb-1'),
      throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 409)),
    );
  });
}
