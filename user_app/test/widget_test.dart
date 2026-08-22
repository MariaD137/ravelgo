import 'package:flutter_test/flutter_test.dart';
import 'package:ravelgo_driver/main.dart';
import 'package:ravelgo_driver/views/Login/login.dart';
import 'package:ravelgo_driver/views/SplashScreen/SplashScreen.dart';

void main() {
  testWidgets('app boots to the splash screen, then navigates to Login', (WidgetTester tester) async {
    await tester.pumpWidget(MyApp());
    expect(find.byType(SplashScreen), findsOneWidget);

    // Flush the splash screen's 5-second navigation timer instead of
    // leaving it pending — an un-flushed Timer here fails the test with
    // "A Timer is still pending even after the widget tree was disposed."
    // pumpAndSettle then drains the route-transition animation the
    // Timer's pushReplacement kicks off.
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expect(find.byType(Login), findsOneWidget);
  });
}
