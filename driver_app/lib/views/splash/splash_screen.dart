import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ravelgo_driver_app/views/auth/login_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

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
    _navigateTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const LoginScreen()),
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
          child: Image.asset('assets/ravel_go_driver_badge.png'),
        ),
      ),
    );
  }
}
