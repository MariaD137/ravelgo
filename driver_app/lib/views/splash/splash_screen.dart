import 'package:flutter/material.dart';
import 'package:ravelgo_driver_app/services/auth_service.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';
import 'package:ravelgo_driver_app/views/auth/login_screen.dart';
import 'package:ravelgo_driver_app/views/shell/driver_shell.dart';
import 'package:ravelgo_driver_app/widgets/app_page_route.dart';

/// Startup gate. Restores a persisted Cognito session (refreshing the access
/// token if needed) BEFORE deciding where to route, so a signed-in driver who
/// refreshes the page lands back on the shell rather than the login screen.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    // Restore the session and keep a short minimum splash so it doesn't flash.
    final results = await Future.wait<dynamic>([
      AuthService.restoreSession(),
      Future<void>.delayed(const Duration(milliseconds: 900)),
    ]);
    if (!mounted) return;
    final restored = results.first == true;
    Navigator.of(context).pushReplacement(
      AppPageRoute(
        builder: (_) => restored ? const DriverShell() : const LoginScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Padding(
        padding: const EdgeInsets.all(80.0),
        child: Center(
          child: Image.asset('assets/ravel_go_driver_badge.png'),
        ),
      ),
    );
  }
}
