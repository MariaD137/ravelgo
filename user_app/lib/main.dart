import 'dart:async';
import 'package:flutter/material.dart';
import 'package:ravelgo_user_app/services/auth_service.dart';
import 'package:ravelgo_user_app/services/notification_navigation.dart';
import 'package:ravelgo_user_app/services/push_notification_service.dart';
import 'package:ravelgo_user_app/services/stripe_service.dart';
import 'package:ravelgo_user_app/views/SplashScreen/SplashScreen.dart';
import 'package:ravelgo_user_app/theme/app_theme.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Lets a tapped device push notification (delivered while the app was
/// backgrounded or terminated) navigate the same way an in-app notification
/// tap does — see PushNotificationService.onNotificationTapped and
/// openNotificationReference. There is no BuildContext available at that
/// point (the tap can arrive before any screen has built), so navigation
/// goes through this key instead.
final navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  // Build the persistent-storage-backed Cognito pool before the first frame so
  // a stored session can be restored on startup (survives browser refresh).
  await AuthService.init();
  // Configure Stripe with the publishable key (no-op if unconfigured). Payment
  // actions surface a clear error rather than crashing when it isn't set.
  await StripeService.init();
  // Best-effort, and a genuine no-op when push isn't configured for this
  // build — covers the "already signed in from a restored session" case;
  // login.dart also calls this after a fresh sign-in.
  unawaited(PushNotificationService.configureAndRegister());
  PushNotificationService.onNotificationTapped = (referenceType, referenceId) {
    final navigator = navigatorKey.currentState;
    if (navigator == null) return;
    openNotificationReference(navigator, referenceType: referenceType, referenceId: referenceId);
  };
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: "RavelGo",
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: SplashScreen(),
      // RavelGo is a phone-shaped app. On a wide desktop browser window
      // (there's no way to tell a plain web build it's "really" a phone),
      // stretching every screen edge-to-edge looks broken and forces
      // fixed-height images/maps into extreme aspect ratios. Cap every
      // screen at a phone-like width and letterbox the rest instead.
      builder: (context, child) {
        return Container(
          color: AppColors.background,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: child,
            ),
          ),
        );
      },
    );
  }
}
