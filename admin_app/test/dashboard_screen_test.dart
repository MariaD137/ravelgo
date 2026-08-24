import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ravelgo_admin/services/admin_api.dart';
import 'package:ravelgo_admin/services/auth_session.dart';
import 'package:ravelgo_admin/views/dashboard/dashboard_screen.dart';

class _FakeAuth implements AuthTokenProvider {
  @override
  Future<String?> getAccessToken() async => 'fake-token';
}

http.Response _dashboardResponse({int activeTrips = 0, int onlineDrivers = 0, int pendingApprovals = 0}) {
  return http.Response(
    jsonEncode({'activeTrips': activeTrips, 'onlineDrivers': onlineDrivers, 'pendingApprovals': pendingApprovals}),
    200,
  );
}

http.Response _fleetResponse({List<Map<String, dynamic>> drivers = const []}) {
  final online = drivers.where((d) => d['isOnline'] == true).length;
  return http.Response(
    jsonEncode({
      'counts': {
        'total': drivers.length,
        'online': online,
        'offline': drivers.length - online,
        'active': drivers.length,
        'pendingReview': 0,
        'suspended': 0,
      },
      'drivers': drivers,
    }),
    200,
  );
}

AdminApi _apiWithHandler(Future<http.Response> Function(http.Request) handler) {
  return AdminApi(baseUrl: 'https://api.test', authTokenProvider: _FakeAuth(), client: MockClient(handler));
}

void main() {
  testWidgets('shows the real online-driver count from the API, not the old hardcoded 112', (tester) async {
    final api = _apiWithHandler((req) async {
      if (req.url.path.endsWith('/admin/dashboard')) {
        return _dashboardResponse(activeTrips: 3, onlineDrivers: 24, pendingApprovals: 1);
      }
      return _fleetResponse();
    });

    await tester.pumpWidget(MaterialApp(home: DashboardScreen(api: api)));
    await tester.pumpAndSettle();

    expect(find.text('24'), findsOneWidget);
    expect(find.text('112'), findsNothing);
  });

  testWidgets('shows a loading indicator before the KPIs resolve', (tester) async {
    final completer = Completer<http.Response>();
    final api = _apiWithHandler((req) => completer.future);

    await tester.pumpWidget(MaterialApp(home: DashboardScreen(api: api)));
    await tester.pump();

    expect(find.text('Loading your dashboard...'), findsOneWidget);

    completer.complete(_dashboardResponse());
    await tester.pumpAndSettle();
  });

  testWidgets('shows an error state with a working retry button on failure', (tester) async {
    var callCount = 0;
    final api = _apiWithHandler((req) async {
      callCount++;
      if (callCount <= 2) {
        // Both fetchDashboardKpis and fetchFleetPresence fire on the first
        // load — fail both so the screen's combined Future.wait rejects.
        return http.Response(
          jsonEncode({
            'error': {'message': 'Unable to load dashboard'},
          }),
          500,
        );
      }
      if (req.url.path.endsWith('/admin/dashboard')) return _dashboardResponse(onlineDrivers: 5);
      return _fleetResponse();
    });

    await tester.pumpWidget(MaterialApp(home: DashboardScreen(api: api)));
    await tester.pumpAndSettle();

    expect(find.text('Unable to load dashboard'), findsOneWidget);
    final retryButton = find.text('Try again');
    expect(retryButton, findsOneWidget);

    await tester.tap(retryButton);
    await tester.pumpAndSettle();

    expect(find.text('Unable to load dashboard'), findsNothing);
    expect(find.text('5'), findsOneWidget);
  });

  testWidgets('shows "No drivers online right now" when the fleet is empty, not a fabricated list', (tester) async {
    final api = _apiWithHandler((req) async {
      if (req.url.path.endsWith('/admin/dashboard')) return _dashboardResponse();
      return _fleetResponse();
    });

    await tester.pumpWidget(MaterialApp(home: DashboardScreen(api: api)));
    await tester.pumpAndSettle();

    expect(find.text('No drivers online right now'), findsOneWidget);
  });

  testWidgets('renders an online driver with "Location unavailable" rather than fabricated coordinates', (tester) async {
    final api = _apiWithHandler((req) async {
      if (req.url.path.endsWith('/admin/dashboard')) return _dashboardResponse(onlineDrivers: 1);
      return _fleetResponse(drivers: [
        {
          'id': 'd1',
          'name': 'Ada Obi',
          'email': 'ada@example.com',
          'status': 'ACTIVE',
          'isOnline': true,
          'onlineSince': DateTime.now().toIso8601String(),
          'vehicle': 'Toyota Camry (ABC-1)',
          'location': 'Location unavailable',
        },
      ]);
    });

    await tester.pumpWidget(MaterialApp(home: DashboardScreen(api: api)));
    await tester.pumpAndSettle();

    expect(find.textContaining('Ada Obi'), findsOneWidget);
    expect(find.textContaining('Location unavailable'), findsOneWidget);
  });
}
