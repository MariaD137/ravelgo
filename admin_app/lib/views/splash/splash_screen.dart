import 'package:flutter/material.dart';
import 'package:ravelgo_admin/theme/app_theme.dart';
import 'package:ravelgo_admin/views/auth/admin_login_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const AdminLoginScreen()),
      );
    });
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
