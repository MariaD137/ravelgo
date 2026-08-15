import 'package:flutter/material.dart';

class RequestDetailsView extends StatefulWidget {
  const RequestDetailsView({Key? key}) : super(key: key);

  @override
  State<RequestDetailsView> createState() => _RequestDetailsViewState();
}

class _RequestDetailsViewState extends State<RequestDetailsView> {
  int offerAmount = 7000;
  bool autoAccept = false;

  final Color gold = const Color(0xFFFFD700);
  final Color lightGold = const Color(0xFFF3E5A0);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F4F4),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              /// Close Button
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: const Icon(Icons.close, size: 26),
              ),

              const SizedBox(height: 25),

              /// Title
              const Text(
                "Request",
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                ),
              ),

              const SizedBox(height: 25),

              /// Route Label
              const Text(
                "Route",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),

              const SizedBox(height: 15),

              /// Pickup
              Row(
                children: const [
                  Icon(Icons.circle_outlined,
                      size: 18, color: Colors.lightGreen),
                  SizedBox(width: 12),
                  Text(
                    "Denco court 1",
                    style: TextStyle(fontSize: 16),
                  ),
                ],
              ),

              const SizedBox(height: 15),

              /// Destination
              Row(
                children: const [
                  Icon(Icons.location_on,
                      size: 20, color: Color(0xFF8A6A00)),
                  SizedBox(width: 12),
                  Text(
                    "Destination",
                    style: TextStyle(fontSize: 16),
                  ),
                ],
              ),

              const SizedBox(height: 25),

              /// Estimated Fare
              RichText(
                text: TextSpan(
                  style: const TextStyle(
                    fontSize: 16,
                    color: Colors.black87,
                  ),
                  children: [
                    const TextSpan(text: "Estimated fare: "),
                    TextSpan(
                      text: "NGN 8,000",
                      style: TextStyle(
                        color: const Color(0xFF8A6A00),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              /// Rider Offer
              RichText(
                text: TextSpan(
                  style: const TextStyle(
                    fontSize: 16,
                    color: Colors.black87,
                  ),
                  children: [
                    const TextSpan(text: "Riders offer: "),
                    TextSpan(
                      text: "NGN 7,500",
                      style: TextStyle(
                        color: const Color(0xFF8A6A00),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 30),

              /// Your Offer Section
              const Text(
                "Your offer",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),

              const SizedBox(height: 15),

              Row(
                children: [
                  /// Amount
                  Expanded(
                    child: Text(
                      "NGN $offerAmount",
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),

                  /// Light +100 Button
                  _incrementButton(
                    color: lightGold,
                    textColor: Colors.black54,
                    onTap: () {
                      setState(() {
                        offerAmount += 100;
                      });
                    },
                  ),

                  const SizedBox(width: 12),

                  /// Bold +100 Button
                  _incrementButton(
                    color: gold,
                    textColor: Colors.black,
                    onTap: () {
                      setState(() {
                        offerAmount += 100;
                      });
                    },
                  ),
                ],
              ),

              const SizedBox(height: 25),

              /// Auto Accept Switch
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    "Auto-accept offer",
                    style: TextStyle(fontSize: 16),
                  ),
                  Switch(
                    value: autoAccept,
                    onChanged: (value) {
                      setState(() {
                        autoAccept = value;
                      });
                    },
                  )
                ],
              ),

              const Spacer(),

              /// Accept Button
              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: gold,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Feature coming soon')),
                    );
                  },
                  child: const Text(
                    "Accept",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.black,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 15),

              /// Decline Button
              SizedBox(
                width: double.infinity,
                height: 55,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(
                      color: Colors.red,
                      width: 1.5,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Feature coming soon')),
                    );
                  },
                  child: const Text(
                    "Decline",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.red,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _incrementButton({
    required Color color,
    required Color textColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(Icons.add, size: 18, color: textColor),
            const SizedBox(width: 6),
            Text(
              "100",
              style: TextStyle(
                color: textColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}