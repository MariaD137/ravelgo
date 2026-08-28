
import 'package:flutter/material.dart';
import 'package:ravelgo_user_app/views/Signup/DriverInformation.dart';
import 'package:ravelgo_user_app/theme/app_theme.dart';

class VerifyAccountScreen extends StatelessWidget {
  final _decoration = InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 16));
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0, iconTheme: IconThemeData(color: AppColors.textPrimary)),
      body: Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Verify your account', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            SizedBox(height: 6),
            Text('Verification code will be sent to this email address.', style: TextStyle(color: AppColors.textSecondary)),
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
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: AppColors.textPrimary),
                child: Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Text('Verify')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
