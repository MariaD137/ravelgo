import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ravelgo_user_app/main.dart';
import 'package:ravelgo_user_app/views/SplashScreen/SplashScreen.dart';

void main() {
  testWidgets('app boots to the splash screen', (WidgetTester tester) async {
    await tester.pumpWidget(MyApp());
    expect(find.byType(SplashScreen), findsOneWidget);
  });
}
