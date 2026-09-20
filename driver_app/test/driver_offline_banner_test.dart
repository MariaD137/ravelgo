import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ravelgo_driver_app/models/driver_profile.dart';
import 'package:ravelgo_driver_app/services/api_client.dart';
import 'package:ravelgo_driver_app/services/session_guard.dart';
import 'package:ravelgo_driver_app/views/home/driver_home_screen.dart';

/// D-4: an online driver whose connection has dropped used to see "You're
/// online and visible to riders" and a spinner promising to notify them,
/// while nothing was reaching the backend at all. The home screen now says
/// so — and says it only for a real connection failure, never for a backend
/// that answered.
void main() {
  const approvedOnline = DriverProfile(
    firstName: 'Femi',
    status: 'ACTIVE',
    isOnline: true,
  );

  setUp(() {
    dotenv.loadFromString(envString: 'API_BASE_URL=https://api.test.ravelgo');
    SessionGuard.reset();
    SessionGuard.refreshSession = () async => false;
    SessionGuard.clearSession = () async {};
    SessionGuard.hasSession = () => false;
  });

  tearDown(() {
    SessionGuard.reset();
    ApiClient.client = http.Client();
  });

  Widget host() => MaterialApp(
        home: Scaffold(
          body: DriverHomeScreen(
            profile: approvedOnline,
            onOnlineToggle: (_) {},
            onRefresh: () async {},
          ),
        ),
      );

  testWidgets('a reachable backend shows the normal online state', (tester) async {
    ApiClient.client = MockClient((_) async => http.Response(jsonEncode([]), 200));

    await tester.pumpWidget(host());
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text("You're online and visible to riders"), findsOneWidget);
    expect(find.text("Can't reach RavelGo"), findsNothing);
  });

  testWidgets('repeated unreachable polls warn that no ride request can arrive',
      (tester) async {
    ApiClient.client = MockClient((req) async {
      throw http.ClientException('Failed to fetch', req.url);
    });

    await tester.pumpWidget(host());
    // One failure is a blip, not an outage.
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text("Can't reach RavelGo"), findsNothing);

    // The poll runs every 8s; a second failed round is the threshold.
    await tester.pump(const Duration(seconds: 9));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text("Can't reach RavelGo"), findsOneWidget);
    expect(find.text("Online, but RavelGo can't be reached"), findsOneWidget);
    expect(
      find.textContaining('no ride request can either'),
      findsOneWidget,
      reason: 'the driver must be told offers cannot reach them',
    );
    // The reassuring copy must be gone while nothing can actually arrive.
    expect(find.text("You're online and visible to riders"), findsNothing);
    expect(find.textContaining("We'll notify you the moment"), findsNothing);
  });

  testWidgets('a backend that answers with an error is not reported as offline',
      (tester) async {
    // 500 means RavelGo was reached and failed — a different problem, and
    // reporting it as "check your connection" would send the driver chasing
    // their own network for nothing.
    ApiClient.client = MockClient(
        (_) async => http.Response(jsonEncode({'error': 'boom'}), 500));

    await tester.pumpWidget(host());
    await tester.pump(const Duration(seconds: 9));
    await tester.pump(const Duration(seconds: 9));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text("Can't reach RavelGo"), findsNothing);
  });

  testWidgets('the banner clears by itself when the connection returns',
      (tester) async {
    var failing = true;
    ApiClient.client = MockClient((req) async {
      if (failing) throw http.ClientException('Failed to fetch', req.url);
      return http.Response(jsonEncode([]), 200);
    });

    await tester.pumpWidget(host());
    await tester.pump(const Duration(seconds: 9));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text("Can't reach RavelGo"), findsOneWidget);

    failing = false;
    await tester.pump(const Duration(seconds: 9));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text("Can't reach RavelGo"), findsNothing);
    expect(find.text("You're online and visible to riders"), findsOneWidget);
  });
}
