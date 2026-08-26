import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ravelgo_admin/services/admin_api.dart';
import 'package:ravelgo_admin/services/auth_session.dart';
import 'package:ravelgo_admin/views/drivers/driver_detail_screen.dart';

class _FakeAuth implements AuthTokenProvider {
  @override
  Future<String?> getAccessToken() async => 'fake-token';

  @override
  Future<bool> refreshAccessToken() async => false;

  @override
  Future<void> clearSession() async {}
}

Map<String, dynamic> _driverDetailJson() => {
      'id': 'd1',
      'user': {'firstName': 'Ada', 'lastName': 'Obi', 'email': 'ada@example.com'},
      'status': 'ACTIVE',
      'rating': 4.9,
      'totalTrips': 20,
      'subscriptionActive': true,
      'vehicles': [
        {
          'id': 'v1',
          'brand': 'Toyota',
          'model': 'Camry',
          'colour': 'Black',
          'plateNumber': 'ABC-1',
          'year': '2021',
          'vin': null,
          'vehicleType': 'SEDAN',
          'isActive': true,
          'verificationStatus': 'PENDING',
          'verificationReason': null,
          'photos': [],
          'documents': [
            {
              'id': 'doc1',
              'driverId': 'd1',
              'vehicleId': 'v1',
              'title': 'Insurance',
              'documentType': 'INSURANCE',
              'status': 'PENDING',
              'fileKey': 'd1/insurance.pdf',
              'expiryDate': null,
              'rejectionReason': null,
              'reviewedAt': null,
            }
          ],
        }
      ],
      'documents': [],
    };

void main() {
  testWidgets('shows the real driver vehicle and document data from the API', (tester) async {
    final api = AdminApi(
      baseUrl: 'https://api.test',
      authTokenProvider: _FakeAuth(),
      client: MockClient((req) async => http.Response(jsonEncode(_driverDetailJson()), 200)),
    );

    await tester.pumpWidget(MaterialApp(home: DriverDetailScreen(driverId: 'd1', api: api)));
    await tester.pumpAndSettle();

    expect(find.textContaining('Toyota Camry'), findsOneWidget);
    expect(find.text('Insurance'), findsOneWidget);
    expect(find.text('Approve'), findsWidgets);
    expect(find.text('Reject'), findsWidgets);
  });

  testWidgets('rejecting a document requires a non-empty reason before calling the API', (tester) async {
    var reviewCalls = <Map<String, dynamic>>[];
    final api = AdminApi(
      baseUrl: 'https://api.test',
      authTokenProvider: _FakeAuth(),
      client: MockClient((req) async {
        if (req.method == 'PATCH' && req.url.path.contains('/review')) {
          reviewCalls.add(jsonDecode(req.body) as Map<String, dynamic>);
          return http.Response(jsonEncode({'id': 'doc1', 'status': 'REJECTED'}), 200);
        }
        return http.Response(jsonEncode(_driverDetailJson()), 200);
      }),
    );

    await tester.pumpWidget(MaterialApp(home: DriverDetailScreen(driverId: 'd1', api: api)));
    await tester.pumpAndSettle();

    // Tap the document's Reject button (the second "Reject" — the first is
    // the vehicle's own reject button).
    await tester.tap(find.text('Reject').last);
    await tester.pumpAndSettle();

    // Confirm with an empty reason — the dialog's own Reject button is a
    // no-op until text is entered, so nothing should be called yet.
    await tester.tap(find.widgetWithText(TextButton, 'Reject').last);
    await tester.pumpAndSettle();
    expect(reviewCalls, isEmpty);
    expect(find.byType(AlertDialog), findsOneWidget); // dialog still open

    await tester.enterText(find.byType(TextField), 'Insurance certificate is expired');
    await tester.tap(find.widgetWithText(TextButton, 'Reject').last);
    await tester.pumpAndSettle();

    expect(reviewCalls, hasLength(1));
    expect(reviewCalls.first['status'], 'REJECTED');
    expect(reviewCalls.first['rejectionReason'], 'Insurance certificate is expired');
  });
}
