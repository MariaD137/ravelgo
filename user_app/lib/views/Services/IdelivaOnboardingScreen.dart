import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:ravelgo_user/views/Services/IDelivaPage.dart';
import 'IdelivaProfileScreen.dart';

class IdelivaOnboardingScreen extends StatefulWidget {
  @override
  _IdelivaOnboardingScreenState createState() => _IdelivaOnboardingScreenState();
}

class _IdelivaOnboardingScreenState extends State<IdelivaOnboardingScreen> {
  bool _obscurePin = true;
  final TextEditingController _pinController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return  SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.arrow_back),
                    onPressed: () {
                      Navigator.pop(context);
                    },
                  ),
                  Text(
                    'I deliva',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
              SizedBox(height: 10),

              // Banner card
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Color(0xFFF2F2F2),
                  borderRadius: BorderRadius.circular(15),
                  boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4)],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text('hhh',
                              style: TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.bold)),
                          SizedBox(height: 5),
                          Text(
                            'Join us today and turn your time into income as a courier.',
                            style: TextStyle(fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(width: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.asset(
                        'assets/courier.png', // Replace with actual image path
                        width: 118,
                        height: 145,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ],
                ),
              ),

              SizedBox(height: 30),

              // PIN Input
              Text('Enter 6 digit security pin'),
              SizedBox(height: 10),
              TextField(
                controller: _pinController,
                obscureText: _obscurePin,
                maxLength: 6,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  counterText: "",
                  border: OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePin ? Icons.visibility_off : Icons.visibility,
                    ),
                    onPressed: () {
                      setState(() {
                        _obscurePin = !_obscurePin;
                      });
                    },
                  ),
                  hintText: 'Enter PIN',
                ),
              ),

              SizedBox(height: 20),

              // Done Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.yellow[700],
                    padding: EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (context) => IdelivaProfileScreen()),
                    );
                  },
                  child: Text(
                    'Done',
                    style: TextStyle(color: Colors.black),
                  ),
                ),
              ),

              SizedBox(height: 20),

              // Register Link
            Center(
              child: Text.rich(
                  TextSpan(
                    text: "Don’t have an I deliva account? ",
                    style: const TextStyle(color: Colors.black54),
                    children: [
                      TextSpan(
                        text: "Register",
                        style: TextStyle(
                        color: Colors.amber[800],
                        fontWeight: FontWeight.w600,
                      ),
                    recognizer: TapGestureRecognizer()
                        ..onTap = () {
                    // Navigate to Register Screen
                         Navigator.push(
                            context,
                             MaterialPageRoute(
                               builder: (_) => const IDelivaPage(), // your screen
                               ),
                             );
                           },
                         ),
                       ],
                    ),
                  ),
              ),
            ],
          ),
        ),
    );
  }
}