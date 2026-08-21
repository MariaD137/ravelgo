import 'package:flutter_test/flutter_test.dart';
import 'package:ravelgo_user/main.dart';
import 'package:ravelgo_user/views/SplashScreen/splash_screen.dart';

void main() {
  testWidgets('app boots to the splash screen', (WidgetTester tester) async {
    await tester.pumpWidget(MyApp());
    expect(find.byType(SplashScreen), findsOneWidget);

    // SplashScreen starts a 2-second Future.delayed in initState to decide
    // where to navigate next; the test framework asserts no Timer is still
    // pending once the test body returns, so this has to run it to
    // completion (via the fake-async clock testWidgets provides) rather
    // than leaving it dangling.
    await tester.pump(const Duration(seconds: 3));
  });
}
