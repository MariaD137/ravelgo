import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ravelgo_admin/services/api/admin_api.dart';
import 'package:ravelgo_admin/services/api/api_client.dart';
import 'package:ravelgo_admin/services/api/auth_provider.dart';

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
  test('getMe() 404s before a profile has been created', () async {
    final client = MockClient((_) async => http.Response(jsonEncode({'error': 'Admin profile not found'}), 404));
    final api = AdminApi(ApiClient(authProvider: _FixedTokenProvider(), httpClient: client));

    await expectLater(api.getMe(), throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 404)));
  });

  test('createMe() posts firstName/lastName/email and returns the created profile', () async {
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response(jsonEncode({'id': 'admin-1', 'firstName': 'Zara', 'role': 'ADMIN'}), 201);
    });
    final api = AdminApi(ApiClient(authProvider: _FixedTokenProvider(), httpClient: client));

    final result = await api.createMe(firstName: 'Zara', lastName: 'K', email: 'zara@example.com');

    expect(captured.method, 'POST');
    expect(captured.url.path, '/api/admin/me');
    expect(jsonDecode(captured.body), {'firstName': 'Zara', 'lastName': 'K', 'email': 'zara@example.com'});
    expect(result['role'], 'ADMIN');
  });

  test('getWeeklyReport() fetches the weekly trips/revenue aggregate', () async {
    final client = MockClient(
      (request) async {
        expect(request.url.path, '/api/admin/reports/weekly');
        return http.Response(jsonEncode({'completedTrips': 12, 'revenue': 45000}), 200);
      },
    );
    final api = AdminApi(ApiClient(authProvider: _FixedTokenProvider(), httpClient: client));

    final result = await api.getWeeklyReport();

    expect(result['completedTrips'], 12);
    expect(result['revenue'], 45000);
  });
}
