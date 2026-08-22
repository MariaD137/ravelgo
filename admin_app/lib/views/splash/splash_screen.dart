import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ravelgo_admin/services/api/auth_provider.dart';
import 'package:ravelgo_admin/views/auth/admin_login_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.authProvider});

  final AuthProvider authProvider;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  Timer? _navigateTimer;

  @override
  void initState() {
    super.initState();
    // A cancellable Timer, not Future.delayed: dispose() below can cancel
    // it outright rather than relying only on the mounted-check to no-op
    // after the fact — the mounted check alone still leaves the timer
    // pending (visible as a test-framework "Timer still pending" failure,
    // and unnecessary work if this screen is disposed early).
    _navigateTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => AdminLoginScreen(authProvider: widget.authProvider)),
      );
    });
  }

  @override
  void dispose() {
    _navigateTimer?.cancel();
    super.dispose();
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
