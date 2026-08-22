import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ravelgo_admin/services/api/api_client.dart';
import 'package:ravelgo_admin/services/api/auth_provider.dart';

class _FixedTokenProvider implements AuthProvider {
  _FixedTokenProvider(this.token);
  final String? token;

  @override
  Future<String?> getAccessToken() async => token;

  @override
  Future<bool> isAuthenticated() async => token != null;

  @override
  Future<void> login({required String username, required String password}) async {
    throw UnimplementedError('not used by these tests');
  }

  @override
  Future<void> logout() async {
    throw UnimplementedError('not used by these tests');
  }
}

void main() {
  test('get() attaches the bearer token and returns decoded JSON on 200', () async {
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response(jsonEncode({'ok': true}), 200);
    });
    final api = ApiClient(authProvider: _FixedTokenProvider('tok-123'), httpClient: client);

    final result = await api.get('/api/admin/dashboard');

    expect(result, {'ok': true});
    expect(captured.headers['Authorization'], 'Bearer tok-123');
    expect(captured.headers['Content-Type'], 'application/json');
  });

  test('get() omits Authorization header when no token is available', () async {
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response(jsonEncode({}), 200);
    });
    final api = ApiClient(authProvider: _FixedTokenProvider(null), httpClient: client);

    await api.get('/api/admin/dashboard');

    expect(captured.headers.containsKey('Authorization'), isFalse);
  });

  test('a 403 response throws ApiException carrying the backend error shape', () async {
    final client = MockClient(
      (request) async => http.Response(jsonEncode({'error': 'Forbidden'}), 403),
    );
    final api = ApiClient(authProvider: _FixedTokenProvider('tok'), httpClient: client);

    await expectLater(
      api.get('/api/admin/dashboard'),
      throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 403)),
    );
  });

  test('a socket failure is surfaced as a NETWORK_ERROR ApiException', () async {
    final client = MockClient((request) async => throw const SocketException('no route to host'));
    final api = ApiClient(authProvider: _FixedTokenProvider('tok'), httpClient: client);

    await expectLater(
      api.get('/api/admin/dashboard'),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', 'NETWORK_ERROR')),
    );
  });

  test('a malformed response body is surfaced as an INVALID_RESPONSE ApiException', () async {
    final client = MockClient((request) async => http.Response('not json', 200));
    final api = ApiClient(authProvider: _FixedTokenProvider('tok'), httpClient: client);

    await expectLater(
      api.get('/api/admin/dashboard'),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', 'INVALID_RESPONSE')),
    );
  });
}
