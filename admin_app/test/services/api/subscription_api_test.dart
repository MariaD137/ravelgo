import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ravelgo_admin/services/api/api_client.dart';
import 'package:ravelgo_admin/services/api/auth_provider.dart';
import 'package:ravelgo_admin/services/api/subscription_api.dart';

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
  test('listPlans() returns the plain list the backend sends (unpaginated)', () async {
    final client = MockClient(
      (request) async {
        expect(request.url.path, '/api/subscription-plans');
        return http.Response(
          jsonEncode([
            {'id': 'plan-1', 'name': 'Weekly', 'priceMonthly': 5000},
          ]),
          200,
        );
      },
    );
    final api = SubscriptionApi(ApiClient(authProvider: _FixedTokenProvider(), httpClient: client));

    final result = await api.listPlans();

    expect(result.map((p) => p['id']), ['plan-1']);
  });
}
