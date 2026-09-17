import 'package:flutter/material.dart';
import 'package:ravelgo_admin/services/admin_api.dart';
import 'package:ravelgo_admin/services/api_client.dart';
import 'package:ravelgo_admin/services/auth_service.dart';
import 'package:ravelgo_admin/theme/app_theme.dart';
import 'package:ravelgo_admin/views/auth/admin_login_screen.dart';
import 'package:ravelgo_admin/views/auth/mfa_setup_screen.dart';
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
    if (restored && !AuthService.isAdmin) {
      // A previously-signed-in non-admin must not silently land back on the
      // dashboard just because their session is still valid.
      await AuthService.signOut();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => const AdminLoginScreen(
            initialError: 'You are not authorized to access the RavelGo Admin Console.',
          ),
        ),
      );
      return;
    }
    if (!restored) {
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const AdminLoginScreen()));
      return;
    }
    // A restored session can already hold valid tokens for an admin who
    // finished setting their password but never completed MFA enrollment
    // (completeNewPassword() returns a real session before MFA setup even
    // starts — see mfa_setup_screen.dart) — re-check here too, not just on a
    // fresh sign-in, so quitting mid-enrollment can never skip it on relaunch.
    bool mfaEnabled;
    try {
      mfaEnabled = (await AdminApi.me()).mfaEnabled;
    } on ApiException {
      // A restored session for a legacy admin whose Postgres row is keyed by
      // the wrong cognitoSub (audit Finding A1): attempt the narrow, self-only
      // repair once and retry, same as the fresh sign-in path, so a page
      // refresh is self-healing too. Fail closed to login (carrying the status
      // code so a persistent failure is diagnosable) if it still can't verify.
      try {
        await AdminApi.repairCognitoSub();
        mfaEnabled = (await AdminApi.me()).mfaEnabled;
      } on ApiException catch (e) {
        await AuthService.signOut();
        if (!mounted) return;
        Navigator.of(context).pushReplacement(MaterialPageRoute(
          builder: (_) => AdminLoginScreen(
            initialError: 'Could not verify your admin account (error ${e.statusCode}). Please sign in again.',
          ),
        ));
        return;
      }
    }
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => mfaEnabled ? const AdminShell() : const MfaSetupScreen()),
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
              Image.asset('assets/logo.png', width: 140),
              const SizedBox(height: 12),
              const Text("ADMIN", style: TextStyle(color: AppColors.primary, letterSpacing: 4, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }
}
