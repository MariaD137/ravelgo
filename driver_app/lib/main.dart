import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:ravelgo_driver_app/services/auth_service.dart';
import 'package:ravelgo_driver_app/services/notification_navigation.dart';
import 'package:ravelgo_driver_app/services/push_notification_service.dart';
import 'package:ravelgo_driver_app/services/session_guard.dart';
import 'package:ravelgo_driver_app/views/auth/login_screen.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';
import 'package:ravelgo_driver_app/views/splash/splash_screen.dart';

/// Lets a tapped device push notification (delivered while the app was
/// backgrounded or terminated) navigate the same way an in-app notification
/// tap does — see PushNotificationService.onNotificationTapped and
/// openNotificationReference. There is no BuildContext available at that
/// point (the tap can arrive before any screen has built), so navigation
/// goes through this key instead.
final navigatorKey = GlobalKey<NavigatorState>();

/// Owns the SnackBar shown when a session expires (see _wireSessionExpiry):
/// the message has to survive the navigation back to sign-in, so it cannot
/// come from the Scaffold of the screen being replaced.
final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
/// A session the backend has rejected (401) sends the app straight back to
/// sign-in, from wherever the user happened to be, with one explanation —
/// see services/session_guard.dart for the rule itself. Wired here because
/// this is the only place that owns both the navigator and the messenger.
void _wireSessionExpiry() {
  SessionGuard.onSessionExpired = () {
    scaffoldMessengerKey.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text(SessionGuard.expiredMessage)),
      );
    navigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  };
}


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
  _wireSessionExpiry();
  runApp(const RavelGoDriverApp());
}

class RavelGoDriverApp extends StatelessWidget {
  const RavelGoDriverApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      scaffoldMessengerKey: scaffoldMessengerKey,
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
