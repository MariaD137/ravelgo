// Captures real, on-device renders of the app's cold-start screens (the
// only ones reachable without a signed-in session or a live backend —
// see splash_screen.dart, which routes to Login() once AuthService
// confirms there's no stored session). Run via test_driver/integration_test.dart
// so screenshots land as real PNG files, not just pass/fail assertions.
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ravelgo_user/main.dart' as app;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('capture splash and login screens', (tester) async {
    app.main();
    await tester.pump();
    // Required once per test on Android before any screenshot is taken.
    await binding.convertFlutterSurfaceToImage();
    await tester.pump();
    await binding.takeScreenshot('user_app_01_splash');

    // The splash screen's own Future.delayed(seconds: 2) before it checks
    // AuthService and navigates — real wall-clock time here, since
    // integration_test runs on an actual device, not fake-async.
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    await binding.takeScreenshot('user_app_02_login');
  });
}
