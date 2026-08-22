import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ravelgo_admin/services/api/api_client.dart';
import 'package:ravelgo_admin/services/api/auth_provider.dart';
import 'package:ravelgo_admin/services/api/courier_api.dart';

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
        jsonEncode({
          'data': [
            {'id': 'cr-1'},
          ],
          'total': 1,
          'page': 1,
          'pageSize': 20,
        }),
        200,
      ),
    );
    final api = CourierApi(ApiClient(authProvider: _FixedTokenProvider(), httpClient: client));

    final result = await api.listAll();

    expect(result.map((r) => r['id']), ['cr-1']);
  });

  test('getById() fetches a single courier request', () async {
    final client = MockClient(
      (request) async => http.Response(jsonEncode({'id': 'cr-1', 'status': 'DELIVERED'}), 200),
    );
    final api = CourierApi(ApiClient(authProvider: _FixedTokenProvider(), httpClient: client));

    final result = await api.getById('cr-1');

    expect(result['status'], 'DELIVERED');
  });
}
