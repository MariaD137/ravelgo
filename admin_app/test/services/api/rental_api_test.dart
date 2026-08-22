import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ravelgo_admin/services/api/api_client.dart';
import 'package:ravelgo_admin/services/api/auth_provider.dart';
import 'package:ravelgo_admin/services/api/rental_api.dart';

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
  test('listListings() unwraps the paginated {data, total} envelope into a list', () async {
    final client = MockClient(
      (request) async => http.Response(
        jsonEncode({
          'data': [
            {'id': 'rl-1', 'status': 'SUBMITTED'},
          ],
          'total': 1,
          'page': 1,
          'pageSize': 20,
        }),
        200,
      ),
    );
    final api = RentalApi(ApiClient(authProvider: _FixedTokenProvider(), httpClient: client));

    final result = await api.listListings();

    expect(result.map((l) => l['id']), ['rl-1']);
  });

  test('decideListing() patches the listing status', () async {
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response(jsonEncode({'id': 'rl-1', 'status': 'APPROVED'}), 200);
    });
    final api = RentalApi(ApiClient(authProvider: _FixedTokenProvider(), httpClient: client));

    final result = await api.decideListing('rl-1', 'APPROVED');

    expect(captured.url.path, '/api/rentals/rl-1/status');
    expect(jsonDecode(captured.body), {'status': 'APPROVED'});
    expect(result['status'], 'APPROVED');
  });

  test('listBookingsForListing() returns the plain list the backend sends (unpaginated)', () async {
    final client = MockClient(
      (request) async => http.Response(
        jsonEncode([
          {'id': 'rb-1'},
          {'id': 'rb-2'},
        ]),
        200,
      ),
    );
    final api = RentalApi(ApiClient(authProvider: _FixedTokenProvider(), httpClient: client));

    final result = await api.listBookingsForListing('rl-1');

    expect(result.map((b) => b['id']), ['rb-1', 'rb-2']);
  });
}
