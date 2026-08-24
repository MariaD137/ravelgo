import 'package:flutter/material.dart';
import 'package:ravelgo_user/services/auth_service.dart';
import 'package:ravelgo_user/views/Login/login.dart';
import 'package:ravelgo_user/views/bottommenu/bottom_navigation_view.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkAuthAndNavigate();
  }

  Future<void> _checkAuthAndNavigate() async {
    await Future.delayed(Duration(seconds: 2));
    if (!mounted) return;

    final isLoggedIn = await AuthService().isLoggedIn();
    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => isLoggedIn ? BottomNavigationView() : Login(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      body: Padding(
        padding: EdgeInsets.all(80.0),
        child: Center(
          child: Image.asset('assets/logo.png'),
        ),
      ),
    );
  }
}
