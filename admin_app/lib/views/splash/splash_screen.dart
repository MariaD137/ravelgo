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

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => isLoggedIn ? const AdminShell() : const AdminLoginScreen(),
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
