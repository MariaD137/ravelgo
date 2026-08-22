import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ravelgo_admin/services/api/api_client.dart';
import 'package:ravelgo_admin/services/api/auth_provider.dart';
import 'package:ravelgo_admin/services/api/support_api.dart';

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
            {'id': 'ticket-1', 'status': 'OPEN'},
          ],
          'total': 1,
          'page': 1,
          'pageSize': 20,
        }),
        200,
      ),
    );
    final api = SupportApi(ApiClient(authProvider: _FixedTokenProvider(), httpClient: client));

    final result = await api.listAll();

    expect(result.map((t) => t['id']), ['ticket-1']);
  });

  test('setStatus() patches the ticket status', () async {
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response(jsonEncode({'id': 'ticket-1', 'status': 'RESOLVED'}), 200);
    });
    final api = SupportApi(ApiClient(authProvider: _FixedTokenProvider(), httpClient: client));

    final result = await api.setStatus('ticket-1', 'RESOLVED');

    expect(captured.url.path, '/api/support-tickets/ticket-1/status');
    expect(jsonDecode(captured.body), {'status': 'RESOLVED'});
    expect(result['status'], 'RESOLVED');
  });
}
