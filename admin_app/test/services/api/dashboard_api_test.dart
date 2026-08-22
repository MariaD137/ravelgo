import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ravelgo_admin/services/api/api_client.dart';
import 'package:ravelgo_admin/services/api/auth_provider.dart';
import 'package:ravelgo_admin/services/api/dashboard_api.dart';

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
  test('getKpis() fetches the dashboard KPI payload', () async {
    late Uri requestedUri;
    final client = MockClient((request) async {
      requestedUri = request.url;
      return http.Response(jsonEncode({'activeTrips': 4, 'onlineDrivers': 9, 'pendingApprovals': 2}), 200);
    });
    final api = DashboardApi(ApiClient(authProvider: _FixedTokenProvider(), httpClient: client));

    final result = await api.getKpis();

    expect(requestedUri.path, '/api/admin/dashboard');
    expect(result['activeTrips'], 4);
    expect(result['pendingApprovals'], 2);
  });
}
