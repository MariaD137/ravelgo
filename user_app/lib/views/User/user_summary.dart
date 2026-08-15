
import 'package:flutter/material.dart';
import 'package:ravelgo/views/bottommenu/BottomNavigationView.dart';

class UserSummary extends StatelessWidget {
  const UserSummary({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 10),

              /// Back Button
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back_ios),
                ),
              ),

              const SizedBox(height: 20),

              /// Profile Avatar
              ClipRRect(
                borderRadius: BorderRadius.circular(60),
                child: SizedBox(
                  width: 60,
                  height: 60,
                  child: Image.asset("assets/fake_profile.png"), // preview image
                ),
              ),

              const SizedBox(height: 16),

              /// Name
              const Text(
                "Thelma Ibeh",
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),

              const SizedBox(height: 8),

              /// Rating Row
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(
                    Icons.star,
                    color: Colors.green,
                    size: 20,
                  ),
                  SizedBox(width: 6),
                  Text(
                    "4.55 Rating",
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 40),

              /// Cards Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children:  [
                  Expanded(
                    child: SummaryCard(
                      title: "Customer ratings",
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: SummaryCard(
                      title: "Acceptance rate",
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: SummaryCard(
                      title: "Acceptance rate",
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 30),

              /// View More
              GestureDetector(
                onTap: () {
                  Navigator.pop(context);
                  BottomNavigationView.globalKey.currentState?.changeTab(3);
                },
                child: const Text(
                  "View more details",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SummaryCard extends StatelessWidget {
  final String title;

  const SummaryCard({
    Key? key,
    required this.title,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      // height: 70,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: const Color(0xFFE8C75F),
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children:  [
          Align(
            alignment: Alignment.center,
            child: Text(title,style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.normal,
            ),
            ),
          ),

          SizedBox(height: 5,),
          Align(
            alignment: Alignment.center,
            child: Image.asset(
              "assets/circle_left.png",
              fit: BoxFit.fill,
              height: 22,
              width: 22,
            ),
          ),
        ],
      ),
    );
  }
}