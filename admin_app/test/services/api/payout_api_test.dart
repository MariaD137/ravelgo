import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ravelgo_admin/services/api/api_client.dart';
import 'package:ravelgo_admin/services/api/auth_provider.dart';
import 'package:ravelgo_admin/services/api/payout_api.dart';

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
  test('calculate() posts driverId/period and returns the calculation', () async {
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response(jsonEncode({'amount': 512.0}), 200);
    });
    final api = PayoutApi(ApiClient(authProvider: _FixedTokenProvider(), httpClient: client));

    final result = await api.calculate(driverId: 'driver-1', period: '2026-08');

    expect(captured.url.path, '/api/payouts/calculate');
    expect(jsonDecode(captured.body), {'driverId': 'driver-1', 'period': '2026-08'});
    expect(result['amount'], 512.0);
  });

  test('create() omits amount when not overriding', () async {
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response(jsonEncode({'id': 'payout-1', 'status': 'PENDING'}), 201);
    });
    final api = PayoutApi(ApiClient(authProvider: _FixedTokenProvider(), httpClient: client));

    final result = await api.create(driverId: 'driver-1', period: '2026-08');

    final body = jsonDecode(captured.body) as Map<String, dynamic>;
    expect(body.containsKey('amount'), isFalse);
    expect(result['status'], 'PENDING');
  });

  test('process()/complete()/fail() hit the expected payout-transition endpoints', () async {
    final requestedPaths = <String>[];
    final client = MockClient((request) async {
      requestedPaths.add(request.url.path);
      return http.Response(jsonEncode({'id': 'payout-1'}), 200);
    });
    final api = PayoutApi(ApiClient(authProvider: _FixedTokenProvider(), httpClient: client));

    await api.process('payout-1');
    await api.complete('payout-1', transactionId: 'txn-1');
    await api.fail('payout-1', failureReason: 'bank rejected');

    expect(requestedPaths, [
      '/api/payouts/payout-1/process',
      '/api/payouts/payout-1/complete',
      '/api/payouts/payout-1/fail',
    ]);
  });

  test('list() unwraps the paginated {data, total} envelope and forwards status/driverId filters', () async {
    late Uri requestedUri;
    final client = MockClient((request) async {
      requestedUri = request.url;
      return http.Response(
        jsonEncode({
          'data': [
            {'id': 'payout-1'},
          ],
          'total': 1,
          'page': 1,
          'pageSize': 20,
        }),
        200,
      );
    });
    final api = PayoutApi(ApiClient(authProvider: _FixedTokenProvider(), httpClient: client));

    final result = await api.list(status: 'PENDING', driverId: 'driver-1');

    expect(requestedUri.queryParameters['status'], 'PENDING');
    expect(requestedUri.queryParameters['driverId'], 'driver-1');
    expect(result.map((p) => p['id']), ['payout-1']);
  });
}
