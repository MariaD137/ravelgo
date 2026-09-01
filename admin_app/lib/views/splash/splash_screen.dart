import 'package:flutter/material.dart';
import 'package:ravelgo_admin/services/auth_service.dart';
import 'package:ravelgo_admin/theme/app_theme.dart';
import 'package:ravelgo_admin/views/auth/admin_login_screen.dart';
import 'package:ravelgo_admin/views/shell/admin_shell.dart';

/// Startup gate. Restores a persisted Cognito session (refreshing the access
/// token if needed) BEFORE deciding where to route, so a signed-in admin who
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
      MaterialPageRoute(
        builder: (_) => restored ? const AdminShell() : const AdminLoginScreen(),
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "RavelGo",
                style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold, color: AppColors.textPrimary, letterSpacing: -0.5),
              ),
              const SizedBox(height: 12),
              const Text("ADMIN", style: TextStyle(color: AppColors.primary, letterSpacing: 4, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }
}
