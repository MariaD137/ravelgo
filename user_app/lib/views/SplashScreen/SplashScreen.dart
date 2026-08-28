import 'package:flutter/material.dart';
import 'package:ravelgo_user_app/theme/app_theme.dart';
import 'package:ravelgo_user_app/views/Login/login.dart';

class SplashScreen extends StatefulWidget {
  @override
  _SplashScreenState createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    // Simulate a delay for the splash screen
    Future.delayed(Duration(seconds: 5), () {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => Login()),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: const Padding(
        padding: EdgeInsets.all(80.0),
        child: Center(
          child: Text(
            "RavelGo",
            style: TextStyle(fontSize: 34, fontWeight: FontWeight.bold, color: AppColors.primary, letterSpacing: -0.5),
          ),
        ),
      ),
    );
  }
}