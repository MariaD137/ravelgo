import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ravelgo_admin/services/api/api_client.dart';
import 'package:ravelgo_admin/services/api/auth_provider.dart';
import 'package:ravelgo_admin/services/api/trip_api.dart';

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
  test('listAll() unwraps the paginated {data, total} envelope into a list', () async {
    final client = MockClient(
      (request) async => http.Response(
        jsonEncode({'data': [{'id': 'trip-1'}], 'total': 1, 'page': 1, 'pageSize': 20}),
        200,
      ),
    );
    final api = TripApi(ApiClient(authProvider: _FixedTokenProvider(), httpClient: client));

    final result = await api.listAll();

    expect(result.map((t) => t['id']), ['trip-1']);
  });

  test('getById() fetches a single trip', () async {
    final client = MockClient((request) async => http.Response(jsonEncode({'id': 'trip-1', 'status': 'MATCHED'}), 200));
    final api = TripApi(ApiClient(authProvider: _FixedTokenProvider(), httpClient: client));

    final result = await api.getById('trip-1');

    expect(result['status'], 'MATCHED');
  });

  test('setStatus() patches the trip status', () async {
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response(jsonEncode({'id': 'trip-1', 'status': 'DISPUTED'}), 200);
    });
    final api = TripApi(ApiClient(authProvider: _FixedTokenProvider(), httpClient: client));

    final result = await api.setStatus('trip-1', 'DISPUTED');

    expect(captured.url.path, '/api/trips/trip-1/status');
    expect(jsonDecode(captured.body), {'status': 'DISPUTED'});
    expect(result['status'], 'DISPUTED');
  });
}
