import 'package:flutter/material.dart';
import 'package:ravelgo_user_app/views/AccountView/EReceiptPage.dart';

import 'Account.dart';

class SubscriptionSuccessPage extends StatelessWidget {
  const SubscriptionSuccessPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F6F6),
      body: SafeArea(
        child: Column(
          children: [

            /// BACK BUTTON
            Padding(
              padding: const EdgeInsets.all(16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                    ),
                    child: const Icon(Icons.arrow_back),
                  ),
                ),
              ),
            ),

            /// CONTENT
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [

                  /// SUCCESS ICON
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.green, width: 4),
                    ),
                    child: const Icon(
                      Icons.check,
                      size: 70,
                      color: Colors.green,
                    ),
                  ),

                  const SizedBox(height: 20),

                  /// TITLE
                  const Text(
                    "Congratulation!",
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                    ),
                  ),

                  const SizedBox(height: 10),

                  /// DESCRIPTION
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 40),
                    child: Text(
                      "You have successfully subscribed yearly plan.\nYou can download your E-receipt Now",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.black54),
                    ),
                  ),
                ],
              ),
            ),

            /// BUTTONS
            Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
              decoration: const BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(color: Colors.black12, blurRadius: 10),
                ],
              ),
              child: Column(
                children: [

                  /// PRIMARY BUTTON
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => EReceiptPage()),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFFD500),
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text("View E-receipt"),
                    ),
                  ),

                  const SizedBox(height: 10),

                  /// SECONDARY BUTTON
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.pushAndRemoveUntil(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const Accountview(),
                          ),
                              (route) => false,
                        );
                      },
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: Colors.grey.shade400),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text("Go to Home"),
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