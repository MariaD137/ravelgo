import 'package:flutter/material.dart';
import 'package:ravelgo_rider_app/views/Signup/CreateAccount.dart';
import 'package:ravelgo_rider_app/views/bottommenu/BottomNavigationView.dart';


class Login extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        // leading: IconButton(
        //   icon: Icon(Icons.close),
        //   color: Colors.black,
        //   onPressed: () => Navigator.of(context).pop(),
        // ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Sign in',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'Hi! Welcome back, you’ve been missed',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey[600],
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 32),
              TextField(
                decoration: InputDecoration(
                  labelText: 'Email',
                  border: OutlineInputBorder(),
                  hintText: 'example@mail.com',
                ),
              ),
              SizedBox(height: 16),
              TextField(
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'Password',
                  border: OutlineInputBorder(),
                  hintText: 'Enter password',
                  suffixIcon: IconButton(
                    icon: Icon(Icons.visibility_off),
                    onPressed: () {},
                  ),
                ),
              ),
              SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  child: Text(
                    'Forgot Password?',
                    style: TextStyle(color: Colors.yellow[700]),
                  ),
                  onPressed: () {
                    // Navigator.push(context,
                    //   MaterialPageRoute(builder: (context) => resetpassword()),
                    // );
                  },
                ),
              ),
              SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                  child: ElevatedButton(
                      onPressed: () {
                        Navigator.of(context).pushAndRemoveUntil(
                          MaterialPageRoute(builder: (context) => BottomNavigationView()),
                              (Route<dynamic> route) => false,
                        );
                    },
                  child: Text('Sign in'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.yellow[700],
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    textStyle: TextStyle(fontSize: 18),
                  ),
                ),
              ),
              SizedBox(height: 32),
              TextButton(
                onPressed: () {
                  Navigator.push(context,
                    MaterialPageRoute(builder: (context) => CreateAccountScreen()),
                  );
                },
                child: Text.rich(
                  TextSpan(
                    text: "Don’t have an account? ",
                    style: TextStyle(color: Colors.black),
                    children: [
                      TextSpan(
                        text: "Sign up",
                        style: TextStyle(color: Color(0xFF665600)),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}