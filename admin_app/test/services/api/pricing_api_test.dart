import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ravelgo_admin/services/api/api_client.dart';
import 'package:ravelgo_admin/services/api/auth_provider.dart';
import 'package:ravelgo_admin/services/api/pricing_api.dart';

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
  test('listPricingRules() returns the plain list the backend sends (unpaginated)', () async {
    final client = MockClient(
      (request) async => http.Response(
        jsonEncode([
          {'id': 'pr-1', 'name': 'Standard'},
        ]),
        200,
      ),
    );
    final api = PricingApi(ApiClient(authProvider: _FixedTokenProvider(), httpClient: client));

    final result = await api.listPricingRules();

    expect(result.map((r) => r['id']), ['pr-1']);
  });

  test('createPricingRule() posts the rule fields', () async {
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response(jsonEncode({'id': 'pr-1', 'name': 'Standard'}), 201);
    });
    final api = PricingApi(ApiClient(authProvider: _FixedTokenProvider(), httpClient: client));

    final result = await api.createPricingRule(name: 'Standard', baseFare: 2, perKm: 1, perMinute: 0.2);

    expect(captured.url.path, '/api/pricing-rules');
    expect(jsonDecode(captured.body), {'name': 'Standard', 'baseFare': 2, 'perKm': 1, 'perMinute': 0.2});
    expect(result['id'], 'pr-1');
  });

  test('updatePricingRule() sends only the provided fields', () async {
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response(jsonEncode({'id': 'pr-1', 'active': false}), 200);
    });
    final api = PricingApi(ApiClient(authProvider: _FixedTokenProvider(), httpClient: client));

    await api.updatePricingRule('pr-1', active: false);

    expect(captured.url.path, '/api/pricing-rules/pr-1');
    expect(jsonDecode(captured.body), {'active': false});
  });

  test('listSurgeZones() returns the plain list the backend sends (unpaginated)', () async {
    final client = MockClient(
      (request) async => http.Response(
        jsonEncode([
          {'id': 'sz-1', 'name': 'Downtown'},
        ]),
        200,
      ),
    );
    final api = PricingApi(ApiClient(authProvider: _FixedTokenProvider(), httpClient: client));

    final result = await api.listSurgeZones();

    expect(result.map((z) => z['id']), ['sz-1']);
  });

  test('createSurgeZone() posts the zone fields', () async {
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response(jsonEncode({'id': 'sz-1'}), 201);
    });
    final api = PricingApi(ApiClient(authProvider: _FixedTokenProvider(), httpClient: client));

    await api.createSurgeZone(name: 'Downtown', location: 'CBD', multiplier: 1.5);

    final body = jsonDecode(captured.body) as Map<String, dynamic>;
    expect(body['name'], 'Downtown');
    expect(body['multiplier'], 1.5);
    expect(body.containsKey('startsAt'), isFalse);
  });

  test('updateSurgeZone() sends only the provided fields', () async {
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response(jsonEncode({'id': 'sz-1', 'active': true}), 200);
    });
    final api = PricingApi(ApiClient(authProvider: _FixedTokenProvider(), httpClient: client));

    await api.updateSurgeZone('sz-1', active: true);

    expect(captured.url.path, '/api/surge-zones/sz-1');
    expect(jsonDecode(captured.body), {'active': true});
  });
}
