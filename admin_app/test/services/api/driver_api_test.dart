import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ravelgo_admin/services/api/api_client.dart';
import 'package:ravelgo_admin/services/api/auth_provider.dart';
import 'package:ravelgo_admin/services/api/driver_api.dart';

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
  test('listDrivers() unwraps the paginated {data, total} envelope into a list', () async {
    final client = MockClient(
      (request) async => http.Response(
        jsonEncode({
          'data': [
            {'id': 'driver-1'},
          ],
          'total': 1,
          'page': 1,
          'pageSize': 20,
        }),
        200,
      ),
    );
    final api = DriverApi(ApiClient(authProvider: _FixedTokenProvider(), httpClient: client));

    final result = await api.listDrivers();

    expect(result.map((d) => d['id']), ['driver-1']);
  });

  test('getById() fetches a single driver with vehicles and documents', () async {
    final client = MockClient(
      (request) async => http.Response(jsonEncode({'id': 'driver-1', 'vehicles': [], 'documents': []}), 200),
    );
    final api = DriverApi(ApiClient(authProvider: _FixedTokenProvider(), httpClient: client));

    final result = await api.getById('driver-1');

    expect(result['id'], 'driver-1');
  });

  test('setStatus() patches the driver status', () async {
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response(jsonEncode({'id': 'driver-1', 'status': 'SUSPENDED'}), 200);
    });
    final api = DriverApi(ApiClient(authProvider: _FixedTokenProvider(), httpClient: client));

    final result = await api.setStatus('driver-1', 'SUSPENDED');

    expect(captured.url.path, '/api/drivers/driver-1/status');
    expect(jsonDecode(captured.body), {'status': 'SUSPENDED'});
    expect(result['status'], 'SUSPENDED');
  });
}
