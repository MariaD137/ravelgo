import 'package:flutter/material.dart';
import 'package:ravelgo_admin/services/auth_service.dart';
import 'package:ravelgo_admin/views/auth/admin_login_screen.dart';
import 'package:ravelgo_admin/views/shell/admin_shell.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkAuthAndNavigate();
  }

  Future<void> _checkAuthAndNavigate() async {
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;

    final isLoggedIn = await AuthService().isLoggedIn();
    if (!mounted) return;

    // A remembered session might belong to an account that's since been
    // removed from the Admin group (or never was one) — re-check group
    // membership on every launch, not just at sign-in time. See
    // admin_login_screen.dart's _signIn for why this is UI-only, not the
    // real authorization boundary.
    final isAdmin = isLoggedIn && await AuthService().isInGroup('Admin');
    if (!mounted) return;
    if (isLoggedIn && !isAdmin) {
      await AuthService().signOut();
    }
    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => isAdmin ? const AdminShell() : const AdminLoginScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      body: Padding(
        padding: const EdgeInsets.all(80.0),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset('assets/logo.png'),
              const SizedBox(height: 12),
              const Text("ADMIN", style: TextStyle(color: Color(0xFFFFD500), letterSpacing: 4, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }
}
