import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ravelgo_driver_app/models/driver_profile.dart';
import 'package:ravelgo_driver_app/services/auth_session.dart';
import 'package:ravelgo_driver_app/services/driver_api.dart';
import 'package:ravelgo_driver_app/views/home/driver_home_screen.dart';

class _FakeAuth implements AuthTokenProvider {
  @override
  Future<String?> getAccessToken() async => 'fake-token';

  @override
  Future<bool> refreshAccessToken() async => false;

  @override
  Future<void> clearSession() async {}
}

DriverApi _apiWithHandler(Future<http.Response> Function(http.Request) handler) {
  return DriverApi(
    baseUrl: 'https://api.test',
    authTokenProvider: _FakeAuth(),
    client: MockClient((request) async => handler(request)),
  );
}

void main() {
  testWidgets('shows a loading indicator while the summary is fetched', (tester) async {
    // A Completer the test controls directly, rather than a real delay —
    // pumping one frame here must show "loading" before the request is
    // ever allowed to resolve.
    final responseCompleter = Completer<http.Response>();
    final api = _apiWithHandler((req) => responseCompleter.future);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DriverHomeScreen(profile: const DriverProfile(), onOnlineToggle: (_) {}, api: api),
      ),
    ));
    await tester.pump();

    expect(find.text('Loading your dashboard...'), findsOneWidget);

    // Let the pending request resolve so the test doesn't leak a timer.
    responseCompleter.complete(http.Response('{}', 200));
    await tester.pumpAndSettle();
  });

  testWidgets('shows real summary values once loaded, not hardcoded placeholders', (tester) async {
    final api = _apiWithHandler((req) async {
      return http.Response(
        jsonEncode({
          'isOnline': true,
          'lastOnlineAt': DateTime.now().toIso8601String(),
          'tripsToday': 6,
          'grossFareToday': 23000,
          'platformFeeToday': 4600,
          'netEarningsToday': 18400,
          'onlineHoursToday': 5.33,
          'rating': 4.8,
          'totalTrips': 214,
        }),
        200,
      );
    });

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DriverHomeScreen(profile: const DriverProfile(), onOnlineToggle: (_) {}, api: api),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('₦18400'), findsOneWidget);
    expect(find.text('6'), findsOneWidget);
    expect(find.text('No activity yet'), findsNothing);
  });

  testWidgets('shows "No activity yet" when the driver has no trips or online time today', (tester) async {
    final api = _apiWithHandler((req) async {
      return http.Response(
        jsonEncode({
          'isOnline': false,
          'lastOnlineAt': null,
          'tripsToday': 0,
          'grossFareToday': 0,
          'platformFeeToday': 0,
          'netEarningsToday': 0,
          'onlineHoursToday': 0,
          'rating': 5.0,
          'totalTrips': 0,
        }),
        200,
      );
    });

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DriverHomeScreen(profile: const DriverProfile(), onOnlineToggle: (_) {}, api: api),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('No activity yet'), findsOneWidget);
  });

  testWidgets('shows an error state with a working retry button', (tester) async {
    var callCount = 0;
    final api = _apiWithHandler((req) async {
      callCount++;
      if (callCount == 1) {
        return http.Response(
          jsonEncode({
            'error': {'message': 'Unable to load dashboard'},
          }),
          500,
        );
      }
      return http.Response(
        jsonEncode({
          'isOnline': false,
          'lastOnlineAt': null,
          'tripsToday': 2,
          'grossFareToday': 1000,
          'platformFeeToday': 200,
          'netEarningsToday': 800,
          'onlineHoursToday': 1,
          'rating': 5.0,
          'totalTrips': 10,
        }),
        200,
      );
    });

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DriverHomeScreen(profile: const DriverProfile(), onOnlineToggle: (_) {}, api: api),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Unable to load dashboard'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);

    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(find.text('Unable to load dashboard'), findsNothing);
    expect(find.text('₦800'), findsOneWidget);
  });
}
