import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ravelgo_admin/services/api/api_client.dart';
import 'package:ravelgo_admin/services/api/auth_provider.dart';
import 'package:ravelgo_admin/services/api/loyalty_api.dart';

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
  test('listTiers() returns the plain list the backend sends', () async {
    final client = MockClient(
      (request) async {
        expect(request.url.path, '/api/loyalty-tiers');
        return http.Response(jsonEncode([{'id': 'tier-1', 'name': 'Gold'}]), 200);
      },
    );
    final api = LoyaltyApi(ApiClient(authProvider: _FixedTokenProvider(), httpClient: client));

    final result = await api.listTiers();

    expect(result.map((t) => t['id']), ['tier-1']);
  });

  test('listPromotions() returns the plain list the backend sends', () async {
    final client = MockClient(
      (request) async {
        expect(request.url.path, '/api/promotions');
        return http.Response(jsonEncode([{'id': 'promo-1', 'code': 'WELCOME10'}]), 200);
      },
    );
    final api = LoyaltyApi(ApiClient(authProvider: _FixedTokenProvider(), httpClient: client));

    final result = await api.listPromotions();

    expect(result.map((p) => p['code']), ['WELCOME10']);
  });

  test('createPromotion() posts code/description/discountPercent and returns the created promo', () async {
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response(jsonEncode({'id': 'promo-2', 'code': 'SAVE20'}), 201);
    });
    final api = LoyaltyApi(ApiClient(authProvider: _FixedTokenProvider(), httpClient: client));

    final result = await api.createPromotion(code: 'SAVE20', description: '20% off', discountPercent: 20);

    expect(captured.url.path, '/api/promotions');
    expect(jsonDecode(captured.body), {'code': 'SAVE20', 'description': '20% off', 'discountPercent': 20});
    expect(result['code'], 'SAVE20');
  });
}
