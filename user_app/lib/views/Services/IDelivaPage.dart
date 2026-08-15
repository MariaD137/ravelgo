import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:ravelgo_user/views/Services/BasicDetailsPage.dart';
import 'package:ravelgo_user/views/Services/ReferralCodePage.dart';
import 'package:ravelgo_user/views/Services/VehicleInfoPage.dart';

class IDelivaPage extends StatefulWidget {
  const IDelivaPage({super.key});

  @override
  State<IDelivaPage> createState() => _IDelivaPageState();
}

class _IDelivaPageState extends State<IDelivaPage> {

  bool basicDone = false;
  bool vehicleDone = false;
  bool referralDone = false;

  bool get isAllDone => basicDone && vehicleDone && referralDone;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F6F6),
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
                    "I deliva",
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
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [

                    /// CARD
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black12,
                            blurRadius: 8,
                          )
                        ],
                      ),
                      child: Column(
                        children: [
                          _tile(
                            title: "Basic details",
                            isDone: basicDone,
                            onTap: () {
                              setState(() => basicDone = true);
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const BasicDetailsPage(),
                                ),
                              );
                            },
                          ),
                          _divider(),

                          _tile(
                            title: "Vehicle Info",
                            subtitle: "if vehicle would be used for delivery",
                            isDone: vehicleDone,
                            onTap: () {
                              setState(() => vehicleDone = true);
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const VehicleInfoPage(),
                                ),
                              );
                            },
                          ),
                          _divider(),

                          _tile(
                            title: "Referral code",
                            subtitle: "if you have a refferal code",
                            isDone: referralDone,
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const ReferralCodePage(),
                                ),
                              );
                              setState(() => referralDone = true);
                            },
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 30),

                    /// DONE BUTTON
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: isAllDone ? () {
                          Navigator.pop(context);
                        } : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isAllDone
                              ? const Color(0xFFFFD500)
                              : const Color(0xFFE6D89C),
                          foregroundColor: Colors.black,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          "Done",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 14),

                    /// TERMS TEXT
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text.rich(
                        TextSpan(
                          text: "By clicking “Submit,” you agree with our ",
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.black54,
                          ),
                          children: [
                            TextSpan(
                              text: "Terms and Condition",
                              style: const TextStyle(
                                color: Colors.green,
                                decoration: TextDecoration.underline,
                              ),
                              recognizer: TapGestureRecognizer()
                                ..onTap = () {},
                            ),
                            const TextSpan(text: " and "),
                            TextSpan(
                              text: "Privacy Policy",
                              style: const TextStyle(
                                color: Colors.green,
                                decoration: TextDecoration.underline,
                              ),
                              recognizer: TapGestureRecognizer()
                                ..onTap = () {},
                            ),
                          ],
                        ),
                        textAlign: TextAlign.center,
                      ),
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

  /// TILE
  Widget _tile({
    required String title,
    String? subtitle,
    required bool isDone,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ],
              ),
            ),

            /// STATUS ICON
            if (isDone)
              const Icon(Icons.check_circle, color: Colors.green, size: 20),

            const SizedBox(width: 8),

            const Icon(Icons.chevron_right, size: 18),
          ],
        ),
      ),
    );
  }

  /// DIVIDER
  Widget _divider() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Divider(
        height: 1,
        thickness: 1,
        color: Colors.grey.shade300,
      ),
    );
  }

}