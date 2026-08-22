import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ravelgo_driver_app/services/api/api_client.dart';
import 'package:ravelgo_driver_app/services/api/auth_token_provider.dart';

class _FixedTokenProvider implements AuthTokenProvider {
  _FixedTokenProvider(this.token);
  final String? token;

  @override
  Future<String?> getAccessToken() async => token;
}

void main() {
  test('get() attaches the bearer token and returns decoded JSON on 200', () async {
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response(jsonEncode({'ok': true}), 200);
    });
    final api = ApiClient(tokenProvider: _FixedTokenProvider('tok-123'), httpClient: client);

    final result = await api.get('/api/drivers/me');

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
    final api = ApiClient(tokenProvider: _FixedTokenProvider(null), httpClient: client);

    await api.get('/api/drivers/me');

    expect(captured.headers.containsKey('Authorization'), isFalse);
  });

  test('a 409 DRIVER_BUSY response throws ApiException carrying the backend conflict shape', () async {
    final body = {
      'code': 'DRIVER_BUSY',
      'message': 'Driver is currently assigned to an active ride.',
      'activeAssignmentType': 'RIDE',
      'activeAssignmentId': 'trip-1',
    };
    final client = MockClient((request) async => http.Response(jsonEncode(body), 409));
    final api = ApiClient(tokenProvider: _FixedTokenProvider('t'), httpClient: client);

    await expectLater(
      api.patch('/api/courier-requests/1/accept'),
      throwsA(
        isA<ApiException>()
            .having((e) => e.statusCode, 'statusCode', 409)
            .having((e) => e.code, 'code', 'DRIVER_BUSY')
            .having((e) => e.body?['activeAssignmentType'], 'activeAssignmentType', 'RIDE'),
      ),
    );
  });

  test('a non-JSON / empty error body still throws a usable ApiException', () async {
    final client = MockClient((request) async => http.Response('', 500));
    final api = ApiClient(tokenProvider: _FixedTokenProvider('t'), httpClient: client);

    await expectLater(
      api.get('/api/health'),
      throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 500)),
    );
  });

  test('query parameters are encoded onto the request URI', () async {
    late Uri requestedUri;
    final client = MockClient((request) async {
      requestedUri = request.url;
      return http.Response(jsonEncode({'data': []}), 200);
    });
    final api = ApiClient(tokenProvider: _FixedTokenProvider('t'), httpClient: client);

    await api.get('/api/courier-requests/available', query: {'page': 2, 'pageSize': 10});

    expect(requestedUri.queryParameters['page'], '2');
    expect(requestedUri.queryParameters['pageSize'], '10');
  });

  test('a SocketException (no connectivity) is wrapped as ApiException(code: NETWORK_ERROR)', () async {
    final client = MockClient((request) async => throw const SocketException('no route to host'));
    final api = ApiClient(tokenProvider: _FixedTokenProvider('t'), httpClient: client);

    await expectLater(
      api.get('/api/health'),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', 'NETWORK_ERROR')),
    );
  });

  test('a request that never responds in time is wrapped as ApiException(code: TIMEOUT)', () async {
    final client = MockClient((request) async {
      await Future<void>.delayed(const Duration(seconds: 5));
      return http.Response('{}', 200);
    });
    final api = ApiClient(tokenProvider: _FixedTokenProvider('t'), httpClient: client, timeout: const Duration(milliseconds: 50));

    await expectLater(
      api.get('/api/health'),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', 'TIMEOUT')),
    );
  });

  test('a non-JSON success body is wrapped as ApiException(code: INVALID_RESPONSE)', () async {
    final client = MockClient((request) async => http.Response('not json at all {{{', 200));
    final api = ApiClient(tokenProvider: _FixedTokenProvider('t'), httpClient: client);

    await expectLater(
      api.get('/api/health'),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', 'INVALID_RESPONSE')),
    );
  });
}
