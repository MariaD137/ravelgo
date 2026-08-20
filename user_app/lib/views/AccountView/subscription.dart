import 'package:flutter/material.dart';
import 'package:ravelgo_user/views/AccountView/subscription_success_page.dart';

class SubscriptionPage extends StatefulWidget {
  const SubscriptionPage({super.key});

  @override
  State<SubscriptionPage> createState() => _SubscriptionPageState();
}

class _SubscriptionPageState extends State<SubscriptionPage> {
  int selectedIndex = 0;

  final plans = [
    {
      "title": "Daily",
      "price": "NGN5,000",
      "tag": "Popular",
      "save": null,
    },
    {
      "title": "Monthly",
      "price": "NGN8,000",
      "tag": null,
      "save": "Save 30%",
    },
    {
      "title": "Yearly",
      "price": "NGN12,000",
      "tag": "Best Value",
      "save": "Save 50%",
    },
  ];

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
                    "Choose a Plan",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),

            /// MAIN CONTENT
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [

                    /// TITLE
                    const Text(
                      "Select a plan",
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.black54,
                      ),
                    ),

                    const SizedBox(height: 16),

                    /// PLAN ROW (2 CARDS)
                    SizedBox(
                      height: 120,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: plans.length,
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        separatorBuilder: (_, _) => const SizedBox(width: 12),
                        itemBuilder: (context, index) {
                          return SizedBox(
                            width: 200, // fixed card width (important)
                            child: _planCard(index),
                          );
                        },
                      ),
                    ),

                    /// THIRD CARD


                    const SizedBox(height: 20),

                    /// FEATURES BOX
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: const Color(0xFFFFD500),
                          width: 1.2,
                        ),
                        color: Colors.white,
                      ),
                      child: Column(
                        children: [
                          _featureItem(
                              "Ability to accept and complete a ride for 24 hours"),
                          const SizedBox(height: 12),
                          _featureItem("Standard subscription rate"),
                        ],
                      ),
                    ),

                    /// BALANCE SPACE (IMPORTANT FIX)
                    const Expanded(child: SizedBox()),
                  ],
                ),
              ),
            ),

            /// BOTTOM BUTTON (FIXED)
            Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
              decoration: const BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 12,
                    offset: Offset(0, -4),
                  ),
                ],
              ),
              child: SafeArea(
                top: false,
                child: SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => SubscriptionSuccessPage()),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFD500),
                      foregroundColor: Colors.black,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: Text(
                      "Continue - ${plans[selectedIndex]["price"]}",
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
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

  /// PLAN CARD
  Widget _planCard(int index) {
    final plan = plans[index];
    final isSelected = selectedIndex == index;

    return GestureDetector(
      onTap: () => setState(() => selectedIndex = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected
                ? const Color(0xFFFFD500)
                : Colors.grey.shade300,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                if (plan["tag"] != null)
                  Text(
                    plan["tag"].toString(),
                    style: TextStyle(
                      fontSize: 11,
                      color: plan["tag"] == "Best Value"
                          ? Colors.blue
                          : Colors.orange,
                      fontWeight: FontWeight.w600,
                    ),
                  ),

                const SizedBox(height: 6),

                Text(
                  plan["title"].toString(),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),

                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      plan["price"].toString(),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (plan["save"] != null) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.black,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          plan["save"].toString(),
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),

            if (isSelected)
              const Positioned(
                right: 0,
                top: 0,
                child: Icon(Icons.check, size: 18),
              ),
          ],
        ),
      ),
    );
  }

  /// FEATURE ITEM
  Widget _featureItem(String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          Icons.check_circle_outline,
          size: 18,
          color: Color(0xFFFFD500),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 13, height: 1.4),
          ),
        ),
      ],
    );
  }
}