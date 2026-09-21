import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ravelgo_admin/services/api_client.dart';
import 'package:ravelgo_admin/services/session_guard.dart';
import 'package:ravelgo_admin/views/drivers/driver_detail_screen.dart';

/// Gap 1 (driver vehicle information): proves GET /api/drivers/:id's
/// `vehicles` array actually reaches the screen, not just that
/// AdminDriverVehicle.fromJson parses it correctly in isolation.
void main() {
  setUp(() {
    dotenv.loadFromString(envString: 'API_BASE_URL=https://api.test.ravelgo');
    SessionGuard.reset();
    SessionGuard.hasSession = () => true;
  });

  tearDown(() {
    SessionGuard.reset();
    ApiClient.client = http.Client();
  });

  Map<String, dynamic> driverJson({required List<Map<String, dynamic>> vehicles}) => {
        'id': 'drv-1',
        'status': 'ACTIVE',
        'isOnline': true,
        'rating': 4.8,
        'totalTrips': 12,
        'user': {
          'id': 'usr-1',
          'firstName': 'Ada',
          'lastName': 'Okafor',
          'email': 'ada@example.com',
          'phoneNumber': '08000000000',
        },
        'documents': const [],
        'vehicles': vehicles,
      };

  testWidgets(
    'a driver with vehicle data renders the vehicle brand, model, plate and approval status',
    (tester) async {
      ApiClient.client = MockClient((req) async {
        return http.Response(
          jsonEncode(driverJson(vehicles: [
            {
              'id': 'veh-1',
              'brand': 'Toyota',
              'model': 'Camry',
              'colour': 'Black',
              'plateNumber': 'ABC-123-XY',
              'year': '2019',
              'isPrimary': true,
              'listedForRental': false,
              'vehicleClass': 'Sedan',
              'approvalStatus': 'PENDING',
            },
          ])),
          200,
        );
      });

      await tester.pumpWidget(
        const MaterialApp(home: DriverDetailScreen(driverId: 'drv-1')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Vehicles'), findsOneWidget);
      expect(find.textContaining('Toyota'), findsOneWidget);
      expect(find.textContaining('Camry'), findsOneWidget);
      expect(find.textContaining('ABC-123-XY'), findsOneWidget);
      expect(find.text('Pending'), findsOneWidget);
      expect(find.text('Primary'), findsOneWidget);
      // A vehicle awaiting review offers both actions; only APPROVED hides
      // "Approve" and only REJECTED hides "Reject" (see the widget's
      // approvalStatus-gated buttons).
      expect(find.text('Approve'), findsOneWidget);
      expect(find.text('Reject'), findsOneWidget);
    },
  );

  testWidgets(
    'a driver with no vehicles shows the empty state instead of a blank list',
    (tester) async {
      ApiClient.client = MockClient((req) async {
        return http.Response(jsonEncode(driverJson(vehicles: const [])), 200);
      });

      await tester.pumpWidget(
        const MaterialApp(home: DriverDetailScreen(driverId: 'drv-1')),
      );
      await tester.pumpAndSettle();

      expect(find.text("This driver hasn't added any vehicles yet."), findsOneWidget);
    },
  );

  testWidgets(
    'a rejected vehicle shows its rejection reason and hides the Reject button',
    (tester) async {
      ApiClient.client = MockClient((req) async {
        return http.Response(
          jsonEncode(driverJson(vehicles: [
            {
              'id': 'veh-2',
              'brand': 'Honda',
              'model': 'Accord',
              'colour': 'Grey',
              'plateNumber': 'XYZ-987-AB',
              'year': '2021',
              'isPrimary': false,
              'listedForRental': false,
              'approvalStatus': 'REJECTED',
              'rejectionReason': 'Plate photo is blurry',
            },
          ])),
          200,
        );
      });

      await tester.pumpWidget(
        const MaterialApp(home: DriverDetailScreen(driverId: 'drv-1')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Reason: Plate photo is blurry'), findsOneWidget);
      expect(find.text('Reject'), findsNothing);
      expect(find.text('Approve'), findsOneWidget);
    },
  );
}
