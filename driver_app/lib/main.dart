import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:ravelgo_driver_app/services/auth_service.dart';
import 'package:ravelgo_driver_app/services/notification_navigation.dart';
import 'package:ravelgo_driver_app/services/push_notification_service.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';
import 'package:ravelgo_driver_app/views/splash/splash_screen.dart';

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
  // Best-effort, and a genuine no-op when push isn't configured for this
  // build — covers the "already signed in from a restored session" case;
  // login_screen.dart also calls this after a fresh sign-in.
  unawaited(PushNotificationService.configureAndRegister());
  PushNotificationService.onNotificationTapped = (type, referenceType, referenceId) {
    final navigator = navigatorKey.currentState;
    if (navigator == null) return;
    openNotificationReference(navigator, referenceType: referenceType, referenceId: referenceId, type: type);
  };
  runApp(const RavelGoDriverApp());
}

class RavelGoDriverApp extends StatelessWidget {
  const RavelGoDriverApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: "RavelGo Driver",
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: const SplashScreen(),
      // Phone-shaped app viewed in an ordinary wide desktop browser window
      // still needs to look like a phone screen, not stretch edge to edge.
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
