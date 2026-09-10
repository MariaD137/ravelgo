// Real end-to-end verification of the booking button chain:
//   FindDriverScreen "Find a driver" button
//     -> _findDriver()
//     -> BookingApi.requestTrip()
//     -> ApiClient.post() (real http.post, real headers)
//     -> a REAL running backend server (RavelGo Express + Prisma + Postgres)
//     -> POST /api/trips creates a REAL Trip row and matches a REAL driver
//     -> the app navigates to SearchDriverScreen showing the matched driver
//
// This does NOT mock the network layer or the backend — it drives the actual
// production widgets and services against a live local server (started
// separately for this verification: see docs in the accompanying report).
// The only test-only step is seeding AuthService's public session fields with
// a locally-fabricated (unsigned) JWT-shaped token, exactly mirroring how the
// backend's own test suite stubs Cognito verification for the same purpose —
// nothing here is shipped in the app.
import 'dart:convert';

import 'package:amazon_cognito_identity_dart_2/cognito.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ravelgo_user_app/services/auth_service.dart';
import 'package:ravelgo_user_app/views/TexiModule/FindDriverScreen.dart';
import 'package:ravelgo_user_app/views/TexiModule/SearchDriverScreen.dart';

String _fakeJwt(Map<String, dynamic> claims) {
  String seg(Object o) => base64Url.encode(utf8.encode(jsonEncode(o))).replaceAll('=', '');
  return '${seg({
        'alg': 'none',
      })}.${seg(claims)}.sig';
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    dotenv.loadFromString(envString: 'API_BASE_URL=http://localhost:8080\n');
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final claims = {
      'sub': 'seed-rider-amaka',
      'token_use': 'access',
      'exp': now + 3600,
      'iat': now,
      'email': 'amaka.obi@example.com',
    };
    final jwt = _fakeJwt(claims);
    final idToken = CognitoIdToken(_fakeJwt({...claims, 'email': 'amaka.obi@example.com', 'given_name': 'Amaka', 'family_name': 'Obi'}));
    final accessToken = CognitoAccessToken(jwt);
    // These are the exact public static fields ApiClient/AuthService use —
    // AuthService.validAccessToken() returns AuthService.accessToken directly
    // once AuthService.session.isValid() is true (checked client-side only,
    // by expiry — no signature check happens on the Flutter side, matching
    // how the real SDK behaves).
    AuthService.session = CognitoUserSession(idToken, accessToken);
    AuthService.accessToken = jwt;
  });

  testWidgets(
    'Find a driver button creates a REAL trip on the REAL backend and shows the matched driver',
    (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        home: FindDriverScreen(
          pickup: 'E2E Test Pickup, Lagos',
          destination: 'E2E Test Destination, Lagos',
          pickupLat: 6.601800,
          pickupLng: 3.351500,
          dropoffLat: 6.515800,
          dropoffLng: 3.370700,
        ),
      ));

      // Real GET /api/pricing/quote round trip.
      await tester.pump(); // build
      await tester.pump(const Duration(seconds: 3));

      expect(find.textContaining('Estimated fare'), findsOneWidget,
          reason: 'the real backend quote should have loaded and rendered a real fare');

      final button = find.widgetWithText(ElevatedButton, 'Find a driver');
      expect(button, findsOneWidget);
      final btnWidget = tester.widget<ElevatedButton>(button);
      expect(btnWidget.onPressed, isNotNull, reason: 'button must be enabled once the quote has loaded');

      await tester.tap(button);
      await tester.pump(); // start the request
      await tester.pump(const Duration(seconds: 3)); // real POST /api/trips round trip

      expect(find.byType(SearchDriverScreen), findsOneWidget,
          reason: 'a successful real trip creation must navigate to the live trip screen');

      // The seeded backend driver (Thelma Ibeh) should be auto-matched and
      // her name should be visible on the real response the widget rendered.
      await tester.pump(const Duration(seconds: 1));
      expect(find.textContaining('Thelma'), findsOneWidget,
          reason: 'the REAL matched driver name from the backend must be shown, not a placeholder');
    },
  );
}
