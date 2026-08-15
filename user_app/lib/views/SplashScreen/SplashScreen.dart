import 'package:flutter/material.dart';
import 'package:ravelgo_user/views/Login/login.dart';

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
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => Login()),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor:  const Color(0xFF000000),
      body:  Padding(
        padding: EdgeInsets.all(80.0),
        child: Center(
          child: Image.asset(
            'assets/logo.png',
          ), // You can customize this
        ),
      ),
    );
  }
}