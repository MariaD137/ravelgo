import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ravelgo_rider_app/views/Login/login.dart';

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
    // Simulate a delay for the splash screen. Cancellable in dispose() and
    // mounted-checked before navigating — without both, a widget test (or a
    // real user backgrounding/closing the app during the delay) hits
    // "Navigator operation requested with a context that does not include a
    // Navigator" or a pending-timer assertion after this widget is gone.
    _navigateTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => Login()),
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
      body: const Padding(
        padding: EdgeInsets.all(80.0),
        child: Center(
          child: Image(
            image: AssetImage('assets/logo.png'),
          ),
        ),
      ),
    );
  }
}
