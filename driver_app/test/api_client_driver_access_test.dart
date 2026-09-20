import 'dart:convert';
import 'dart:io';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ravelgo_driver_app/services/api_client.dart';

// The "Your account isn't set up as a driver yet." failure: the backend
// answers 403 on every Driver-only route while the access token predates the
// server granting the Driver group. These tests pin the client's recovery
// (one forced refresh, one retry, only when the refreshed token really has
// the group) and that each failure class is described as itself.
void main() {
  setUpAll(() {
    dotenv.loadFromString(envString: 'API_BASE_URL=https://api.test.invalid');
  });

  setUp(() {
    ApiClient.resetRecoveryWindow();
    ApiClient.recoverDriverAccess = () async => false;
  });

  tearDown(() {
    ApiClient.client = http.Client();
    ApiClient.recoverDriverAccess = () async => false;
  });

  test(
    'a 403 with a stale token is retried once after a refresh that yields the Driver group',
    () async {
      var calls = 0;
      var recoveries = 0;
      ApiClient.client = MockClient((request) async {
        calls++;
        if (calls == 1) {
          return http.Response(
            jsonEncode({'error': 'Insufficient permissions'}),
            403,
          );
        }
        return http.Response(jsonEncode([]), 200);
      });
      ApiClient.recoverDriverAccess = () async {
        recoveries++;
        return true;
      };

      final result = await ApiClient.get('/api/documents/me');
      expect(result, isA<List>());
      expect(calls, 2);
      expect(recoveries, 1);
    },
  );

  test(
    'a 403 stays a 403 when the refreshed token still lacks the Driver group (no retry loop)',
    () async {
      var calls = 0;
      ApiClient.client = MockClient((request) async {
        calls++;
        return http.Response(
          jsonEncode({'error': 'Insufficient permissions'}),
          403,
        );
      });
      ApiClient.recoverDriverAccess = () async => false;

      await expectLater(
        ApiClient.get('/api/documents/me'),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'statusCode', 403),
        ),
      );
      expect(calls, 1);
    },
  );

  test(
    'a network failure is a statusCode-0 ApiException, never a backend answer',
    () async {
      ApiClient.client = MockClient(
        (request) async => throw const SocketException('Failed host lookup'),
      );
      await expectLater(
        ApiClient.get('/api/drivers/me'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.isNetworkFailure,
            'isNetworkFailure',
            isTrue,
          ),
        ),
      );
    },
  );

  test(
    '401, 404 and 500 are surfaced with their own status codes and backend messages',
    () async {
      for (final entry in {
        401: {'error': 'Invalid or expired token'},
        404: {'error': 'Driver profile not found'},
        500: {
          'error': {
            'code': 'DATABASE_ERROR',
            'message': 'Database operation failed',
          },
        },
      }.entries) {
        ApiClient.client = MockClient(
          (request) async => http.Response(jsonEncode(entry.value), entry.key),
        );
        await expectLater(
          ApiClient.get('/api/drivers/me'),
          throwsA(
            isA<ApiException>().having(
              (e) => e.statusCode,
              'statusCode',
              entry.key,
            ),
          ),
        );
      }
    },
  );

  test(
    'describeApiFailure gives each failure class a distinct, honest explanation',
    () {
      final unauthenticated = describeApiFailure(
        ApiException(401, 'Invalid or expired token'),
      );
      final forbidden = describeApiFailure(
        ApiException(403, 'Insufficient permissions'),
      );
      final missing = describeApiFailure(
        ApiException(404, 'Driver profile not found'),
      );
      final server = describeApiFailure(
        ApiException(500, 'Database operation failed'),
      );
      final offline = describeApiFailure(
        ApiException(
          0,
          'Can\'t reach RavelGo (no route). Check your connection and try again.',
        ),
      );

      expect(unauthenticated, contains('session has expired'));
      expect(forbidden, contains('driver access'));
      expect(missing, contains('driver profile hasn\'t been created'));
      expect(server, contains('server problem'));
      expect(offline, contains('Check your connection'));
      // Only the 403 is about not being a driver.
      for (final other in [unauthenticated, missing, server, offline]) {
        expect(other, isNot(contains('driver access')));
      }
      expect({unauthenticated, forbidden, missing, server, offline}.length, 5);
    },
  );
}
