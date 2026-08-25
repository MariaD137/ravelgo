import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ravelgo_admin/services/admin_api.dart';
import 'package:ravelgo_admin/services/auth_session.dart';

/// Tracks calls so tests can assert exactly-once refresh/retry behaviour
/// (see admin_api.dart's _send: one 401 triggers exactly one refresh and
/// one retry — never a loop).
class _CountingAuth implements AuthTokenProvider {
  int refreshCalls = 0;
  int clearSessionCalls = 0;
  final bool refreshSucceeds;

  _CountingAuth({this.refreshSucceeds = true});

  @override
  Future<String?> getAccessToken() async => 'token';

  @override
  Future<bool> refreshAccessToken() async {
    refreshCalls++;
    return refreshSucceeds;
  }

  @override
  Future<void> clearSession() async {
    clearSessionCalls++;
  }
}

void main() {
  test('a single 401 triggers exactly one refresh and one retry, then returns the retried response', () async {
    var callCount = 0;
    final auth = _CountingAuth();
    final api = AdminApi(
      baseUrl: 'https://api.test',
      authTokenProvider: auth,
      client: MockClient((req) async {
        callCount++;
        if (callCount == 1) return http.Response('{"error":"expired"}', 401);
        return http.Response(jsonEncode({'activeTrips': 1, 'onlineDrivers': 2, 'pendingApprovals': 3}), 200);
      }),
    );

    final kpis = await api.fetchDashboardKpis();

    expect(callCount, 2, reason: 'exactly one retry after the refresh — never more');
    expect(auth.refreshCalls, 1);
    expect(auth.clearSessionCalls, 0);
    expect(kpis.activeTrips, 1);
  });

  test('a 401 on the retry itself clears the session and surfaces a sign-in-again error, without retrying again', () async {
    var callCount = 0;
    final auth = _CountingAuth();
    final api = AdminApi(
      baseUrl: 'https://api.test',
      authTokenProvider: auth,
      client: MockClient((req) async {
        callCount++;
        return http.Response('{"error":"expired"}', 401);
      }),
    );

    await expectLater(
      api.fetchDashboardKpis(),
      throwsA(isA<AdminApiException>().having((e) => e.message, 'message', contains('sign in again'))),
    );

    expect(callCount, 2, reason: 'the original attempt plus exactly one retry — no further looping');
    expect(auth.refreshCalls, 1);
    expect(auth.clearSessionCalls, 1);
  });

  test('a failed refresh clears the session and surfaces a sign-in-again error without ever retrying the request', () async {
    var callCount = 0;
    final auth = _CountingAuth(refreshSucceeds: false);
    final api = AdminApi(
      baseUrl: 'https://api.test',
      authTokenProvider: auth,
      client: MockClient((req) async {
        callCount++;
        return http.Response('{"error":"expired"}', 401);
      }),
    );

    await expectLater(
      api.fetchDashboardKpis(),
      throwsA(isA<AdminApiException>().having((e) => e.message, 'message', contains('sign in again'))),
    );

    expect(callCount, 1, reason: 'refresh never succeeded, so the request is never retried');
    expect(auth.refreshCalls, 1);
    expect(auth.clearSessionCalls, 1);
  });

  test('a request that times out surfaces a clear, user-facing timeout message', () async {
    final auth = _CountingAuth();
    final api = AdminApi(
      baseUrl: 'https://api.test',
      authTokenProvider: auth,
      client: MockClient((req) async {
        throw TimeoutException('simulated timeout');
      }),
    );

    await expectLater(
      api.fetchDashboardKpis(),
      throwsA(isA<AdminApiException>().having((e) => e.message, 'message', contains('timed out'))),
    );
  });
}
