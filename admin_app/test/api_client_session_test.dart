import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ravelgo_admin/services/api_client.dart';
import 'package:ravelgo_admin/services/session_guard.dart';

/// X-1 (centralised 401 handling) and X-2 (network error classification):
/// proves ApiClient turns a dead session into exactly one refresh, one
/// retry and one trip back to sign-in, and that a request that never
/// reaches the backend is never presented as a backend answer.
void main() {
  late List<http.Request> sent;
  late int refreshCalls;
  late int signOutCalls;
  late int expiredCallbacks;
  late bool signedIn;

  setUp(() {
    dotenv.loadFromString(envString: 'API_BASE_URL=https://api.test.ravelgo');
    sent = [];
    refreshCalls = 0;
    signOutCalls = 0;
    expiredCallbacks = 0;
    signedIn = true;
    SessionGuard.reset();
    SessionGuard.refreshSession = () async {
      refreshCalls += 1;
      return false;
    };
    SessionGuard.clearSession = () async {
      signOutCalls += 1;
      signedIn = false;
    };
    SessionGuard.hasSession = () => signedIn;
    SessionGuard.onSessionExpired = () => expiredCallbacks += 1;
  });

  tearDown(() {
    SessionGuard.reset();
    SessionGuard.onSessionExpired = null;
    ApiClient.client = http.Client();
  });

  void respond(Iterable<http.Response> script) {
    final queue = script.toList();
    ApiClient.client = MockClient((req) async {
      sent.add(req);
      return queue.length == 1 ? queue.first : queue.removeAt(0);
    });
  }

  http.Response unauthorized() =>
      http.Response(jsonEncode({'error': 'Unauthorized'}), 401);

  test('a successful request is returned decoded and touches nothing else',
      () async {
    respond([http.Response(jsonEncode({'ok': true}), 200)]);
    final body = await ApiClient.get('/api/thing');
    expect(body['ok'], isTrue);
    expect(sent, hasLength(1));
    expect(refreshCalls, 0);
    expect(expiredCallbacks, 0);
  });

  test('a 401 forces one refresh and retries the request once', () async {
    SessionGuard.refreshSession = () async {
      refreshCalls += 1;
      return true;
    };
    respond([unauthorized(), http.Response(jsonEncode({'ok': true}), 200)]);

    final body = await ApiClient.get('/api/thing');
    expect(body['ok'], isTrue);
    expect(refreshCalls, 1, reason: 'exactly one refresh');
    expect(sent, hasLength(2), reason: 'original request retried once');
    expect(signOutCalls, 0, reason: 'the session recovered');
    expect(expiredCallbacks, 0);
  });

  test('a 401 that survives the refresh signs out and returns to sign-in',
      () async {
    SessionGuard.refreshSession = () async {
      refreshCalls += 1;
      return true;
    };
    respond([unauthorized()]);

    await expectLater(
      ApiClient.get('/api/thing'),
      throwsA(
        isA<ApiException>()
            .having((e) => e.statusCode, 'statusCode', 401)
            .having((e) => e.message, 'message', SessionGuard.expiredMessage),
      ),
    );
    expect(refreshCalls, 1);
    expect(sent, hasLength(2), reason: 'retried once, then gave up');
    expect(signOutCalls, 1);
    expect(expiredCallbacks, 1);
  });

  test('a 401 with no usable refresh token gives up without retrying',
      () async {
    respond([unauthorized()]);

    await expectLater(ApiClient.get('/api/thing'), throwsA(isA<ApiException>()));
    expect(refreshCalls, 1);
    expect(sent, hasLength(1), reason: 'refresh failed, so no retry');
    expect(signOutCalls, 1);
    expect(expiredCallbacks, 1);
  });

  test('a burst of 401s produces one refresh, one sign-out, one navigation',
      () async {
    respond([unauthorized()]);

    final results = await Future.wait([
      ApiClient.get('/api/a').then<Object?>((v) => v, onError: (e) => e),
      ApiClient.get('/api/b').then<Object?>((v) => v, onError: (e) => e),
      ApiClient.get('/api/c').then<Object?>((v) => v, onError: (e) => e),
    ]);
    expect(results.every((r) => r is ApiException), isTrue);
    expect(refreshCalls, 1, reason: 'the refresh is shared, not repeated');
    expect(signOutCalls, 1);
    expect(expiredCallbacks, 1, reason: 'the user is sent to sign-in once');
  });

  test('a request that never reaches the backend is a network failure, not a '
      'backend answer', () async {
    ApiClient.client = MockClient((req) async {
      throw http.ClientException('Failed to fetch', req.url);
    });

    await expectLater(
      ApiClient.get('/api/thing'),
      throwsA(
        isA<ApiException>()
            .having((e) => e.statusCode, 'statusCode', 0)
            .having((e) => e.isNetworkFailure, 'isNetworkFailure', true)
            .having((e) => e.message, 'message', contains('Can\'t reach RavelGo')),
      ),
    );
    expect(refreshCalls, 0, reason: 'no network is not an expired session');
    expect(signOutCalls, 0, reason: 'a flaky connection must not sign anyone out');
    expect(expiredCallbacks, 0);
  });

  test('describeApiFailure gives each failure class its own sentence', () {
    expect(
      describeApiFailure(ApiException(0, 'Can\'t reach RavelGo (offline).'),
          what: 'trips'),
      contains('Can\'t reach RavelGo'),
    );
    expect(describeApiFailure(ApiException(401, 'Unauthorized'), what: 'trips'),
        SessionGuard.expiredMessage);
    expect(describeApiFailure(ApiException(500, 'boom'), what: 'trips'),
        contains('server problem'));
    expect(describeApiFailure(Exception('odd'), what: 'trips'),
        contains('Something went wrong'));
    // Every class says something different — that is the whole point.
    final messages = {
      describeApiFailure(ApiException(0, 'x'), what: 'trips'),
      describeApiFailure(ApiException(401, 'x'), what: 'trips'),
      describeApiFailure(ApiException(403, 'x'), what: 'trips'),
      describeApiFailure(ApiException(404, 'x'), what: 'trips'),
      describeApiFailure(ApiException(503, 'x'), what: 'trips'),
    };
    expect(messages, hasLength(5));
  });

  test('the backend\'s nested error envelope is unwrapped to its message',
      () async {
    respond([
      http.Response(
        jsonEncode({
          'error': {'code': 'INTERNAL_SERVER_ERROR', 'message': 'Database is down'}
        }),
        500,
      )
    ]);
    await expectLater(
      ApiClient.get('/api/thing'),
      throwsA(isA<ApiException>()
          .having((e) => e.message, 'message', 'Database is down')),
    );
  });

  test(
      'a 5xx the backend explained is shown in its own words, anything else '
      'stays generic', () {
    // The case that prolonged a real outage: every screen replaced this with
    // "server problem (500)", hiding the one fact that named the cause.
    const schema =
        'Database schema is out of date on this server (pending migrations not applied)';
    final outOfDate = ApiException(500, schema, code: 'DATABASE_ERROR');
    expect(outOfDate.hasReadableServerReason, isTrue);
    expect(describeApiFailure(outOfDate, what: 'your profile'), schema);

    // Payments and upstream services are equally operator-written.
    expect(
      describeApiFailure(
        ApiException(503, 'Payments are not configured on this server yet',
            code: 'PAYMENT_PROVIDER_ERROR'),
        what: 'payment',
      ),
      'Payments are not configured on this server yet',
    );
    expect(
      describeApiFailure(
        ApiException(502, 'Could not reach the location service',
            code: 'UPSTREAM_ERROR'),
        what: 'places',
      ),
      'Could not reach the location service',
    );

    // The catch-all 500 stays generic: that is the branch where an unexpected
    // error could otherwise carry internals.
    final internal = ApiException(500, 'Internal server error',
        code: 'INTERNAL_SERVER_ERROR');
    expect(internal.hasReadableServerReason, isFalse);
    expect(
        describeApiFailure(internal, what: 'trips'), contains('server problem'));

    // An unknown code is never trusted, whatever it says.
    final unknown = ApiException(500, 'relation "public.Secret" does not exist',
        code: 'SOME_NEW_CODE');
    expect(unknown.hasReadableServerReason, isFalse);
    expect(
        describeApiFailure(unknown, what: 'trips'), contains('server problem'));
    expect(describeApiFailure(unknown, what: 'trips'),
        isNot(contains('public.Secret')));

    // No code at all (a bare string body) is also not trusted on a 5xx.
    expect(ApiException(500, 'boom').hasReadableServerReason, isFalse);
    // A 4xx is unaffected: its message was always shown.
    expect(
      describeApiFailure(
          ApiException(400, 'Bad input', code: 'VALIDATION_ERROR'),
          what: 'x'),
      'Bad input',
    );
  });

  test('the error code is parsed off the wire, not invented', () async {
    respond([
      http.Response(
        jsonEncode({
          'error': {
            'code': 'DATABASE_ERROR',
            'message':
                'Database schema is out of date on this server (pending migrations not applied)'
          }
        }),
        500,
      )
    ]);

    await expectLater(
      ApiClient.get('/api/thing'),
      throwsA(isA<ApiException>()
          .having((e) => e.code, 'code', 'DATABASE_ERROR')
          .having(
              (e) => e.hasReadableServerReason, 'hasReadableServerReason', true)),
    );
  });
}
