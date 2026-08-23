import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ravelgo_driver_app/models/driver_operational_state.dart';
import 'package:ravelgo_driver_app/services/api/api_client.dart';
import 'package:ravelgo_driver_app/services/api/auth_provider.dart';
import 'package:ravelgo_driver_app/services/driver_session.dart';
import 'package:ravelgo_driver_app/views/home/driver_home_screen.dart';

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

/// Part 2's requirement — "a driver actively performing a ride or courier
/// job must not be able to navigate into another operational workflow and
/// begin it" — enforced client-side (in addition to the backend's own
/// DriverAssignment rejection) by driver_home_screen.dart hiding the
/// ride/courier entry points whenever DriverSession reports the driver
/// busy. This test exercises that gating directly, independent of any
/// specific screen it might otherwise navigate to.
void main() {
  setUp(() {
    // A MockClient that 404s everything real matching/assignment calls
    // would hit — this file only exercises the operational-state gating
    // (state is set directly via markBusy/reconcile below), not the
    // network calls setOnline()/loadProfile() make.
    final client = MockClient((_) async => http.Response(jsonEncode({'error': 'not used'}), 404));
    DriverSession.resetForTesting(
      authProvider: _FixedTokenProvider(),
      apiClient: ApiClient(authProvider: _FixedTokenProvider(), httpClient: client),
    );
    DriverSession.instance.goOffline();
  });

  Widget pumpableHome() {
    return MaterialApp(
      home: Scaffold(
        drawer: const Drawer(child: SizedBox()),
        body: const DriverHomeScreen(),
      ),
    );
  }

  testWidgets('shows ride/courier actions when online and available', (tester) async {
    DriverSession.instance.goAvailable();
    await tester.pumpWidget(pumpableHome());

    expect(find.text('Listening for ride requests...'), findsOneWidget);
    expect(find.text('View available deliveries'), findsOneWidget);
  });

  testWidgets('hides ride/courier actions and shows a busy banner while on an active ride', (tester) async {
    DriverSession.instance.markBusy(DriverOperationalState.onRide, 'trip-1');
    await tester.pumpWidget(pumpableHome());

    expect(find.text('Listening for ride requests...'), findsNothing);
    expect(find.text('View available deliveries'), findsNothing);
    expect(find.textContaining('on a ride'), findsOneWidget);
  });

  testWidgets('hides ride/courier actions and shows a busy banner while on an active delivery', (tester) async {
    DriverSession.instance.markBusy(DriverOperationalState.onCourier, 'courier-1');
    await tester.pumpWidget(pumpableHome());

    expect(find.text('Listening for ride requests...'), findsNothing);
    expect(find.text('View available deliveries'), findsNothing);
    expect(find.textContaining('on a delivery'), findsOneWidget);
  });

  testWidgets('actions reappear once DriverSession reconciles back to available', (tester) async {
    DriverSession.instance.markBusy(DriverOperationalState.onRide, 'trip-1');
    await tester.pumpWidget(pumpableHome());
    expect(find.text('View available deliveries'), findsNothing);

    DriverSession.instance.reconcile(busy: false);
    await tester.pump();

    expect(find.text('View available deliveries'), findsOneWidget);
  });
}
