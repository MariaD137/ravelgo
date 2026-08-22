import 'package:flutter/material.dart';
import 'package:ravelgo_rider_app/components/basic_components.dart';

class ReferralCodePage extends StatefulWidget {
  const ReferralCodePage({super.key});

  @override
  State<ReferralCodePage> createState() => _ReferralCodePageState();
}

class _ReferralCodePageState extends State<ReferralCodePage> {
  final TextEditingController controller =
  TextEditingController(text: "A5678888");

  bool get isValid => controller.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F6F6),

      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            /// HEADER
            AppComponents.header(context, "Referral code"),

            /// CONTENT
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [

                  /// LABEL
                  const Text(
                    "Enter referral code",
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),

                  const SizedBox(height: 10),

                  /// INPUT FIELD
                  TextField(
                    controller: controller,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 14),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide:
                        BorderSide(color: Colors.grey.shade300),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide:
                        BorderSide(color: Colors.grey.shade300),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide:
                        const BorderSide(color: Colors.black),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const Spacer(),

            /// BUTTON
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: isValid
                      ? () {
                    Navigator.pop(context, controller.text);
                  }
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFD500),
                    foregroundColor: Colors.black,
                    disabledBackgroundColor:
                    const Color(0xFFFFD500).withOpacity(0.4),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    "Done",
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}