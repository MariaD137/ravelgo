import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ravelgo_admin/services/api/api_client.dart';
import 'package:ravelgo_admin/services/api/auth_provider.dart';
import 'package:ravelgo_admin/services/api/rider_api.dart';

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
  test('listRiders() unwraps the paginated {data, total} envelope into a list', () async {
    final client = MockClient(
      (request) async => http.Response(
        jsonEncode({
          'data': [
            {'id': 'rider-1'},
          ],
          'total': 1,
          'page': 1,
          'pageSize': 20,
        }),
        200,
      ),
    );
    final api = RiderApi(ApiClient(authProvider: _FixedTokenProvider(), httpClient: client));

    final result = await api.listRiders();

    expect(result.map((r) => r['id']), ['rider-1']);
  });

  test('getById() fetches a single rider with trip history', () async {
    final client = MockClient(
      (request) async => http.Response(
        jsonEncode({
          'id': 'rider-1',
          'ridesAsRider': [],
        }),
        200,
      ),
    );
    final api = RiderApi(ApiClient(authProvider: _FixedTokenProvider(), httpClient: client));

    final result = await api.getById('rider-1');

    expect(result['id'], 'rider-1');
  });

  test('setSuspended() patches the suspended flag', () async {
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response(jsonEncode({'id': 'rider-1', 'suspended': true}), 200);
    });
    final api = RiderApi(ApiClient(authProvider: _FixedTokenProvider(), httpClient: client));

    final result = await api.setSuspended('rider-1', true);

    expect(captured.url.path, '/api/riders/rider-1/status');
    expect(jsonDecode(captured.body), {'suspended': true});
    expect(result['suspended'], true);
  });
}
