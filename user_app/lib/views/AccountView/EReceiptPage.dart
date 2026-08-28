import 'package:flutter/material.dart';
import 'package:ravelgo_user_app/theme/app_theme.dart';

class EReceiptPage extends StatelessWidget {
  const EReceiptPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [

            /// HEADER
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(Icons.arrow_back),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    "E - Receipt",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),

            /// CONTENT
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [

                    /// BARCODE PLACEHOLDER
                    Container(
                      height: 80,
                      width: double.infinity,
                      color: Colors.white,
                      child: const Center(
                        child: Text("|||||||||||||||||||||||||||||",
                            style: TextStyle(letterSpacing: 2)),
                      ),
                    ),

                    const SizedBox(height: 16),

                    /// DETAILS CARD
                    _card([
                      _row("Plan Details", "Daily"),
                      _row("Purchase Date", "April 24, 2025 | 10:00 AM"),
                      _row("Expiry Date", "April 24, 2025 | 10:00 AM"),
                      _row("Amount", "NGN5,000"),
                      _row("Tax & Fees", "NGN700"),
                      _row("Total", "NGN5,700"),
                    ]),

                    const SizedBox(height: 16),

                    /// USER INFO
                    _card([
                      _row("Name", "John Harry"),
                      _row("Phone Number", "07037530000"),
                      _row("Payment Mode", "Debit card"),
                      _row("Transaction ID", "#RE2564HG23"),
                    ]),
                  ],
                ),
              ),
            ),

            /// BUTTON
            _bottomButton("Download E-receipt", () {}),
          ],
        ),
      ),
    );
  }

  Widget _card(List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: children
            .map((e) => Column(
          children: [
            e,
            const Divider(height: 20),
          ],
        ))
            .toList()
          ..removeLast(),
      ),
    );
  }

  Widget _row(String title, String value) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(color: Colors.black54),
          ),
        ),
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  Widget _bottomButton(String text, VoidCallback onTap) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(color: Colors.black12, blurRadius: 10),
        ],
      ),
      child: SizedBox(
        width: double.infinity,
        height: 48,
        child: ElevatedButton(
          onPressed: onTap,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.black,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          child: Text(text),
        ),
      ),
    );
  }
}