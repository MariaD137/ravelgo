import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ravelgo_rider_app/services/api/api_client.dart';
import 'package:ravelgo_rider_app/services/api/auth_provider.dart';
import 'package:ravelgo_rider_app/services/api/pricing_api.dart';

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
  test('getQuote() sends distanceKm/durationMinutes/zone as query params and returns the fare estimate', () async {
    late Uri requestedUri;
    final client = MockClient((request) async {
      requestedUri = request.url;
      return http.Response(
        jsonEncode({'estimatedFare': 12.5, 'pricingRule': 'Standard', 'surgeMultiplier': 1.0, 'surgeZone': null}),
        200,
      );
    });
    final api = PricingApi(ApiClient(authProvider: _FixedTokenProvider(), httpClient: client));

    final result = await api.getQuote(distanceKm: 5, durationMinutes: 12, zone: 'downtown');

    expect(requestedUri.path, '/api/pricing/quote');
    expect(requestedUri.queryParameters['distanceKm'], '5.0');
    expect(requestedUri.queryParameters['durationMinutes'], '12.0');
    expect(requestedUri.queryParameters['zone'], 'downtown');
    expect(result['estimatedFare'], 12.5);
  });

  test('a 409 (no active pricing rule) surfaces as ApiException', () async {
    final client = MockClient(
      (request) async => http.Response(jsonEncode({'error': 'No active pricing rule configured'}), 409),
    );
    final api = PricingApi(ApiClient(authProvider: _FixedTokenProvider(), httpClient: client));

    await expectLater(
      api.getQuote(distanceKm: 5, durationMinutes: 12),
      throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 409)),
    );
  });
}
