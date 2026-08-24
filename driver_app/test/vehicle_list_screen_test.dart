import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ravelgo_driver_app/services/auth_session.dart';
import 'package:ravelgo_driver_app/services/driver_api.dart';
import 'package:ravelgo_driver_app/views/vehicles/vehicle_list_screen.dart';

class _FakeAuth implements AuthTokenProvider {
  @override
  Future<String?> getAccessToken() async => 'fake-token';
}

DriverApi _apiWithHandler(Future<http.Response> Function(http.Request) handler) {
  return DriverApi(baseUrl: 'https://api.test', authTokenProvider: _FakeAuth(), client: MockClient(handler));
}

Map<String, dynamic> _vehicleJson({
  String id = 'v1',
  String brand = 'Mazda',
  String model = '3',
  String verificationStatus = 'PENDING',
  bool isActive = true,
}) {
  return {
    'id': id,
    'driverId': 'd1',
    'brand': brand,
    'model': model,
    'colour': 'Red',
    'plateNumber': 'XYZ-1',
    'year': '2021',
    'vin': null,
    'vehicleType': 'SEDAN',
    'isPrimary': false,
    'listedForRental': false,
    'isActive': isActive,
    'verificationStatus': verificationStatus,
    'verificationReason': null,
    'photos': [],
  };
}

void main() {
  testWidgets('shows a loading indicator before vehicles resolve', (tester) async {
    final completer = Completer<http.Response>();
    final api = _apiWithHandler((req) => completer.future);

    await tester.pumpWidget(MaterialApp(home: VehicleListScreen(api: api)));
    await tester.pump();

    expect(find.text('Loading your vehicles...'), findsOneWidget);
    completer.complete(http.Response(jsonEncode([]), 200));
    await tester.pumpAndSettle();
  });

  testWidgets('shows real vehicle data from the API, not the old hardcoded Toyota Camry/Honda Accord', (tester) async {
    final api = _apiWithHandler((req) async => http.Response(jsonEncode([_vehicleJson()]), 200));

    await tester.pumpWidget(MaterialApp(home: VehicleListScreen(api: api)));
    await tester.pumpAndSettle();

    expect(find.textContaining('Mazda 3'), findsOneWidget);
    expect(find.textContaining('Toyota Camry'), findsNothing);
    expect(find.textContaining('Honda Accord'), findsNothing);
    expect(find.text('Pending review'), findsOneWidget);
  });

  testWidgets('shows an empty state with no vehicles, not a blank screen', (tester) async {
    final api = _apiWithHandler((req) async => http.Response(jsonEncode([]), 200));

    await tester.pumpWidget(MaterialApp(home: VehicleListScreen(api: api)));
    await tester.pumpAndSettle();

    expect(find.text('No vehicles yet'), findsOneWidget);
  });

  testWidgets('shows an error state with a working retry button', (tester) async {
    var callCount = 0;
    final api = _apiWithHandler((req) async {
      callCount++;
      if (callCount == 1) {
        return http.Response(
          jsonEncode({
            'error': {'message': 'Unable to load your vehicles'},
          }),
          500,
        );
      }
      return http.Response(jsonEncode([_vehicleJson(brand: 'Kia', model: 'Rio')]), 200);
    });

    await tester.pumpWidget(MaterialApp(home: VehicleListScreen(api: api)));
    await tester.pumpAndSettle();

    expect(find.text('Unable to load your vehicles'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(find.text('Unable to load your vehicles'), findsNothing);
    expect(find.textContaining('Kia Rio'), findsOneWidget);
  });

  testWidgets('a deactivated vehicle still shows in the list (not silently removed)', (tester) async {
    final api = _apiWithHandler((req) async => http.Response(
          jsonEncode([_vehicleJson(id: 'v2', brand: 'Nissan', model: 'Altima', isActive: false, verificationStatus: 'APPROVED')]),
          200,
        ));

    await tester.pumpWidget(MaterialApp(home: VehicleListScreen(api: api)));
    await tester.pumpAndSettle();

    expect(find.textContaining('Nissan Altima'), findsOneWidget);
    expect(find.textContaining('Deactivated'), findsOneWidget);
  });
}
