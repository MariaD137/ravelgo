import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ravelgo_user/views/TexiModule/cancel_ride_screen.dart';

// These tests only cover the screen's client-side reason-selection gating —
// tapping "DONE" calls TripService().cancelTrip(), which goes through the
// real (non-injectable) ApiClient singleton, so it isn't safe to trigger in
// a widget test without hitting the network. See api_client.dart: unlike
// DriverApi/AdminApi, ApiClient wraps dart:io HttpClient directly rather
// than an injectable http.Client, so there's no MockClient seam here yet.
void main() {
  testWidgets('the DONE button is disabled until a cancellation reason is selected', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: CancelRideScreen(tripId: 'trip-1')));

    final doneButton = tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'DONE'));
    expect(doneButton.onPressed, isNull);
  });

  testWidgets('selecting a reason enables the DONE button', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: CancelRideScreen(tripId: 'trip-1')));

    await tester.tap(find.text('Long pick up time'));
    await tester.pump();

    final doneButton = tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'DONE'));
    expect(doneButton.onPressed, isNotNull);
  });

  testWidgets('the close button pops without submitting a cancellation', (tester) async {
    var popped = false;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async {
            final result = await Navigator.of(context).push<bool>(
              MaterialPageRoute(builder: (_) => const CancelRideScreen(tripId: 'trip-1')),
            );
            popped = result == false;
          },
          child: const Text('open'),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(popped, isTrue);
  });
}
