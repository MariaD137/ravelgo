import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ravelgo_rider_app/services/api/api_client.dart';
import 'package:ravelgo_rider_app/services/api/auth_provider.dart';
import 'package:ravelgo_rider_app/services/api/courier_api.dart';

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
  test('createRequest() posts the package details and returns the created request', () async {
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response(jsonEncode({'id': 'cr-1', 'status': 'REQUESTED'}), 201);
    });
    final api = CourierApi(ApiClient(authProvider: _FixedTokenProvider(), httpClient: client));

    final result = await api.createRequest(
      pickupAddress: '1 Lekki Rd',
      dropoffAddress: '2 VI Rd',
      packageDescription: 'Documents',
      recipientName: 'Chidi',
      recipientPhone: '+2340000000',
      estimatedFare: 25,
    );

    expect(captured.url.path, '/api/courier-requests');
    final body = jsonDecode(captured.body) as Map<String, dynamic>;
    expect(body['packageDescription'], 'Documents');
    expect(result['id'], 'cr-1');
  });

  test('getById() fetches a courier request by id', () async {
    final client = MockClient(
      (request) async => http.Response(jsonEncode({'id': 'cr-1', 'status': 'ACCEPTED'}), 200),
    );
    final api = CourierApi(ApiClient(authProvider: _FixedTokenProvider(), httpClient: client));

    final result = await api.getById('cr-1');

    expect(result['status'], 'ACCEPTED');
  });

  test('myRequests() unwraps the paginated {data, total} envelope into a list', () async {
    final client = MockClient(
      (request) async => http.Response(
        jsonEncode({
          'data': [
            {'id': 'cr-2'},
          ],
          'total': 1,
          'page': 1,
          'pageSize': 20,
        }),
        200,
      ),
    );
    final api = CourierApi(ApiClient(authProvider: _FixedTokenProvider(), httpClient: client));

    final result = await api.myRequests();

    expect(result.map((r) => r['id']), ['cr-2']);
  });
}
