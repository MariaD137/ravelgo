import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ravelgo_admin/services/api/api_client.dart';
import 'package:ravelgo_admin/services/api/auth_provider.dart';
import 'package:ravelgo_admin/services/api/document_api.dart';

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
  test('review() patches the document status', () async {
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response(jsonEncode({'id': 'doc-1', 'status': 'APPROVED'}), 200);
    });
    final api = DocumentApi(ApiClient(authProvider: _FixedTokenProvider(), httpClient: client));

    final result = await api.review('doc-1', 'APPROVED');

    expect(captured.url.path, '/api/documents/doc-1/review');
    expect(jsonDecode(captured.body), {'status': 'APPROVED'});
    expect(result['status'], 'APPROVED');
  });
}
