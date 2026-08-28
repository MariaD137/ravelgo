import 'package:flutter/material.dart';
import 'package:ravelgo_user_app/views/OtherViews/PrivacyScreenDetail.dart';
class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        leading: const BackButton(color: Colors.black),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: const Text("Privacy", style: TextStyle(color: Colors.black)),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "We value your privacy and are committed to protecting your personal data",
              style: TextStyle(fontSize: 15, height: 1.5),
            ),
            const SizedBox(height: 30),
            Container(
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: const [
                      Expanded(
                        child: Text(
                          "Would you like a copy of your personal data?",
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                        ),
                      ),
                      Icon(Icons.copy, size: 28),
                    ],
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.yellow[700],
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => PrivacyScreenDetail()),
                        );
                      },
                      child: const Text("Continue"),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}