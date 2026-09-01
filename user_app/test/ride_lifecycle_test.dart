import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ravelgo_user_app/views/TexiModule/RateDriverScreen.dart';
import 'package:ravelgo_user_app/views/TexiModule/RequestDriverScreen.dart';
import 'package:ravelgo_user_app/views/TexiModule/RiderTripScreen.dart';

void main() {
  testWidgets('decline removes an offer from the list', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: RequestDriverScreen()));

    expect(find.byType(DriverCard), findsNWidgets(3));
    expect(find.text('Found 3 Drivers'), findsOneWidget);

    await tester.tap(find.text('Decline').first);
    await tester.pump();

    expect(find.byType(DriverCard), findsNWidgets(2));
    expect(find.text('Found 2 Drivers'), findsOneWidget);
  });

  testWidgets('accept enters the trip lifecycle and progresses to rating',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: RequestDriverScreen()));

    await tester.tap(find.text('Accept').first);
    await tester.pumpAndSettle();

    // Accepted -> en route -> arrived -> in progress -> completed -> rate.
    expect(find.byType(RiderTripScreen), findsOneWidget);
    expect(find.text('Driver accepted'), findsOneWidget);

    await tester.pump(const Duration(seconds: 6));
    expect(find.text('Driver en route'), findsOneWidget);

    await tester.pump(const Duration(seconds: 6));
    expect(find.text('Driver has arrived'), findsOneWidget);

    await tester.pump(const Duration(seconds: 6));
    expect(find.text('Trip in progress'), findsOneWidget);
    // Cancel is only offered before pickup.
    expect(find.text('Cancel ride'), findsNothing);

    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expect(find.byType(RateDriverScreen), findsOneWidget);
    expect(find.text('Trip completed'), findsOneWidget);

    // Submit stays disabled until a star is chosen; enabled after.
    final submit = tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Submit rating'));
    expect(submit.onPressed, isNull);
    await tester.tap(find.byIcon(Icons.star_border).first);
    await tester.pump();
    final submitAfter =
        tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Submit rating'));
    expect(submitAfter.onPressed, isNotNull);
  });

  testWidgets('trip can be cancelled before pickup with confirmation',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: RequestDriverScreen()));
    await tester.tap(find.text('Accept').first);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cancel ride'));
    await tester.pumpAndSettle();
    expect(find.text('Cancel this ride?'), findsOneWidget);

    // Keeping the ride leaves the trip screen in place.
    await tester.tap(find.text('Keep ride'));
    await tester.pumpAndSettle();
    expect(find.byType(RiderTripScreen), findsOneWidget);
  });
}
