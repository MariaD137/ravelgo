import 'package:flutter/material.dart';
import 'package:ravelgo_user/views/Driver_Portal/side_menu_driver.dart';

class FAQScreen extends StatelessWidget {
  const FAQScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const SideMenuDriver(initialSelectedItem: "FAQ",),
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              /// HEADER
              Row(
                children: [
                  Builder(
                    builder: (context) => GestureDetector(
                      onTap: () => Scaffold.of(context).openDrawer(),
                      child: Container(
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(color: Colors.black12, blurRadius: 6),
                          ],
                        ),
                        child: const CircleAvatar(
                          backgroundColor: Colors.white,
                          child: Icon(Icons.menu, color: Colors.black),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Image.asset(
                    "assets/ravel_go_driver_badge.png",
                    height: 28,
                  ),
                ],
              ),

              const SizedBox(height: 28),

              const Text(
                "FAQs",
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
              ),

              const SizedBox(height: 24),

              _faqText(),
              const SizedBox(height: 20),
              _faqText(),
              const SizedBox(height: 20),
              _faqText(),
              const SizedBox(height: 20),
              _faqText(),
              const SizedBox(height: 20),
              _faqText(),

              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  Widget _faqText() {
    return const Text(
      "Lorem ipsum dolor sit amet consectetur. Pharetra etiam sit enim quam odio massavehicula non consectetur. Et non pulvinar nec velit nunc. Pellentesque elementum enim sit convallis id.",
      style: TextStyle(fontSize: 15, height: 1.6),
    );
  }
}