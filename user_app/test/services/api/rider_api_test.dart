import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ravelgo_rider_app/services/api/api_client.dart';
import 'package:ravelgo_rider_app/services/api/auth_provider.dart';
import 'package:ravelgo_rider_app/services/api/rider_api.dart';

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
  test('getMe() fetches my rider profile', () async {
    final client = MockClient(
      (request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/api/riders/me');
        return http.Response(jsonEncode({'id': 'rider-1', 'firstName': 'Ada'}), 200);
      },
    );
    final api = RiderApi(ApiClient(authProvider: _FixedTokenProvider(), httpClient: client));

    final result = await api.getMe();

    expect(result['firstName'], 'Ada');
  });

  test('getMe() 404s before a profile has been created', () async {
    final client = MockClient((_) async => http.Response(jsonEncode({'error': 'Rider profile not found'}), 404));
    final api = RiderApi(ApiClient(authProvider: _FixedTokenProvider(), httpClient: client));

    await expectLater(api.getMe(), throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 404)));
  });

  test('createMe() posts firstName/lastName/email and returns the created profile', () async {
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response(jsonEncode({'id': 'rider-1', 'firstName': 'Ada'}), 201);
    });
    final api = RiderApi(ApiClient(authProvider: _FixedTokenProvider(), httpClient: client));

    await api.createMe(firstName: 'Ada', lastName: 'L', email: 'ada@example.com');

    expect(captured.method, 'POST');
    expect(captured.url.path, '/api/riders/me');
    final body = jsonDecode(captured.body) as Map<String, dynamic>;
    expect(body['firstName'], 'Ada');
    expect(body['email'], 'ada@example.com');
    expect(body.containsKey('phoneNumber'), isFalse);
  });

  test('updateMe() PATCHes only the fields given', () async {
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response(jsonEncode({'id': 'rider-1', 'firstName': 'New'}), 200);
    });
    final api = RiderApi(ApiClient(authProvider: _FixedTokenProvider(), httpClient: client));

    final result = await api.updateMe(firstName: 'New');

    expect(captured.method, 'PATCH');
    expect(captured.url.path, '/api/riders/me');
    final body = jsonDecode(captured.body) as Map<String, dynamic>;
    expect(body, {'firstName': 'New'});
    expect(result['firstName'], 'New');
  });
}
