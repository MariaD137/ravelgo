import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ravelgo_driver_app/services/auth_session.dart';
import 'package:ravelgo_driver_app/services/driver_api.dart';
import 'package:ravelgo_driver_app/views/vehicles/add_vehicle_screen.dart';

class _FakeAuth implements AuthTokenProvider {
  @override
  Future<String?> getAccessToken() async => 'fake-token';

  @override
  Future<bool> refreshAccessToken() async => false;

  @override
  Future<void> clearSession() async {}
}

void main() {
  testWidgets('submitting a blank form shows validation errors and never calls the API', (tester) async {
    var callCount = 0;
    final api = DriverApi(
      baseUrl: 'https://api.test',
      authTokenProvider: _FakeAuth(),
      client: MockClient((req) async {
        callCount++;
        return http.Response('{}', 201);
      }),
    );

    await tester.pumpWidget(MaterialApp(home: AddVehicleScreen(api: api)));
    await tester.tap(find.text('Save vehicle'));
    await tester.pump();

    expect(find.text('Required'), findsWidgets);
    expect(callCount, 0); // no fake fallback data was ever submitted
  });

  testWidgets('a valid submission calls the API with the entered values and pops with true', (tester) async {
    Map<String, dynamic>? sentBody;
    final api = DriverApi(
      baseUrl: 'https://api.test',
      authTokenProvider: _FakeAuth(),
      client: MockClient((req) async {
        sentBody = jsonDecode(req.body) as Map<String, dynamic>;
        return http.Response(jsonEncode({'id': 'v1', ...sentBody!, 'photos': []}), 201);
      }),
    );

    bool? poppedWith;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async {
            poppedWith = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => AddVehicleScreen(api: api)));
          },
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'Make *'), 'Toyota');
    await tester.enterText(find.widgetWithText(TextFormField, 'Model *'), 'Corolla');
    await tester.enterText(find.widgetWithText(TextFormField, 'Colour *'), 'Blue');
    await tester.enterText(find.widgetWithText(TextFormField, 'Plate number *'), 'ABC-123');
    await tester.enterText(find.widgetWithText(TextFormField, 'Year *'), '2021');

    await tester.tap(find.text('Save vehicle'));
    await tester.pumpAndSettle();

    expect(sentBody?['brand'], 'Toyota');
    expect(sentBody?['plateNumber'], 'ABC-123');
    expect(sentBody?.containsKey('vin'), false); // omitted, not sent as null
    expect(poppedWith, true);
  });
}
