import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:ravelgo_admin/services/auth_service.dart';
import 'package:ravelgo_admin/services/session_guard.dart';
import 'package:ravelgo_admin/views/auth/admin_login_screen.dart';
import 'package:ravelgo_admin/theme/app_theme.dart';
import 'package:ravelgo_admin/views/splash/splash_screen.dart';

/// The admin app had no navigator key at all, so nothing outside a widget
/// could navigate. Both keys exist for the session-expiry rule below.
final navigatorKey = GlobalKey<NavigatorState>();
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
      MaterialPageRoute(builder: (_) => const AdminLoginScreen()),
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
  _wireSessionExpiry();
  runApp(const RavelGoAdminApp());
}

class RavelGoAdminApp extends StatelessWidget {
  const RavelGoAdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      scaffoldMessengerKey: scaffoldMessengerKey,
      title: "RavelGo Admin",
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: const SplashScreen(),
    );
  }
}
