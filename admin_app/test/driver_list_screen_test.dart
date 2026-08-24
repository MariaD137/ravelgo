import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ravelgo_admin/services/admin_api.dart';
import 'package:ravelgo_admin/services/auth_session.dart';
import 'package:ravelgo_admin/views/drivers/driver_list_screen.dart';

class _FakeAuth implements AuthTokenProvider {
  @override
  Future<String?> getAccessToken() async => 'fake-token';
}

AdminApi _apiWithHandler(Future<http.Response> Function(http.Request) handler) {
  return AdminApi(baseUrl: 'https://api.test', authTokenProvider: _FakeAuth(), client: MockClient(handler));
}

Map<String, dynamic> _pagedDrivers(List<Map<String, dynamic>> drivers) =>
    {'data': drivers, 'page': 1, 'pageSize': 100, 'total': drivers.length};

Map<String, dynamic> _driverJson({String id = 'd1', String status = 'ACTIVE', String firstName = 'Ada', String lastName = 'Obi'}) => {
      'id': id,
      'user': {'firstName': firstName, 'lastName': lastName, 'email': '$firstName@example.com'},
      'status': status,
      'rating': 4.8,
      'totalTrips': 12,
      'subscriptionActive': true,
      'vehicles': [],
    };

void main() {
  testWidgets('shows real drivers from the API, not mock data', (tester) async {
    final api = _apiWithHandler((req) async => http.Response(jsonEncode(_pagedDrivers([_driverJson()])), 200));

    await tester.pumpWidget(MaterialApp(home: DriverListScreen(api: api)));
    await tester.pumpAndSettle();

    expect(find.textContaining('Ada Obi'), findsOneWidget);
    expect(find.text('Active'), findsOneWidget);
  });

  testWidgets('shows an empty state, not a blank screen', (tester) async {
    final api = _apiWithHandler((req) async => http.Response(jsonEncode(_pagedDrivers([])), 200));

    await tester.pumpWidget(MaterialApp(home: DriverListScreen(api: api)));
    await tester.pumpAndSettle();

    expect(find.text('No drivers yet'), findsOneWidget);
  });

  testWidgets('shows an error state with a working retry button', (tester) async {
    var callCount = 0;
    final api = _apiWithHandler((req) async {
      callCount++;
      if (callCount == 1) {
        return http.Response(
          jsonEncode({
            'error': {'message': 'Unable to load drivers'},
          }),
          500,
        );
      }
      return http.Response(jsonEncode(_pagedDrivers([_driverJson(firstName: 'Chinedu')])), 200);
    });

    await tester.pumpWidget(MaterialApp(home: DriverListScreen(api: api)));
    await tester.pumpAndSettle();

    expect(find.text('Unable to load drivers'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Chinedu'), findsOneWidget);
  });
}
