import 'package:flutter/material.dart';
import 'package:ravelgo_user_app/services/auth_service.dart';
import 'package:ravelgo_user_app/theme/app_theme.dart';
import 'package:ravelgo_user_app/views/Login/login.dart';
import 'package:ravelgo_user_app/views/bottommenu/BottomNavigationView.dart';

/// Startup gate. Restores a persisted Cognito session (refreshing the access
/// token if needed) BEFORE deciding where to route, so a signed-in user who
/// refreshes the page lands back on Home rather than the login screen.
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
      MaterialPageRoute(
        builder: (_) => restored ? BottomNavigationView() : const Login(),
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
          child: Image.asset('assets/logo.png', width: 160),
        ),
      ),
    );
  }
}
