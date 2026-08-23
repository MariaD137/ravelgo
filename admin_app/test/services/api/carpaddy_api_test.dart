import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ravelgo_admin/services/api/api_client.dart';
import 'package:ravelgo_admin/services/api/auth_provider.dart';
import 'package:ravelgo_admin/services/api/carpaddy_api.dart';

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
        jsonEncode({'data': [{'id': 'cp-1'}], 'total': 1, 'page': 1, 'pageSize': 20}),
        200,
      ),
    );
    final api = CarPaddyApi(ApiClient(authProvider: _FixedTokenProvider(), httpClient: client));

    final result = await api.listAll();

    expect(result.map((r) => r['id']), ['cp-1']);
  });

  test('decide() patches the request status and surfaces a 409 as ApiException', () async {
    final client = MockClient(
      (request) async => http.Response(jsonEncode({'error': 'Car Paddy request cannot move to APPROVED from status APPROVED'}), 409),
    );
    final api = CarPaddyApi(ApiClient(authProvider: _FixedTokenProvider(), httpClient: client));

    await expectLater(
      api.decide('cp-1', 'APPROVED'),
      throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 409)),
    );
  });

  test('decide() on success returns the updated request', () async {
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response(jsonEncode({'id': 'cp-1', 'status': 'REJECTED'}), 200);
    });
    final api = CarPaddyApi(ApiClient(authProvider: _FixedTokenProvider(), httpClient: client));

    final result = await api.decide('cp-1', 'REJECTED');

    expect(captured.url.path, '/api/car-paddy/cp-1');
    expect(jsonDecode(captured.body), {'status': 'REJECTED'});
    expect(result['status'], 'REJECTED');
  });
}
