
import 'package:flutter/material.dart';
import 'package:ravelgo/views/Signup/DriverInformation.dart';

class VerifyAccountScreen extends StatelessWidget {
  final _decoration = InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 16));
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0, iconTheme: IconThemeData(color: Colors.black)),
      body: Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Verify your account', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            SizedBox(height: 6),
            Text('Verification code will be sent to this email address.', style: TextStyle(color: Colors.grey[600])),
            SizedBox(height: 18),
            Text('OTP'),
            SizedBox(height: 6),
            TextField(decoration: _decoration.copyWith(hintText: 'Enter OTP')),
            SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.push(context,
                    MaterialPageRoute(builder: (context) => DriverInformationScreen()),
                  );
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.yellow[700], foregroundColor: Colors.black),
                child: Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Text('Verify')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
