import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';

void main() {
  testWidgets('primary button renders with given label', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppComponents.primaryButton(text: 'Go online', onPressed: () {}),
        ),
      ),
    );

    expect(find.text('Go online'), findsOneWidget);
  });
}
