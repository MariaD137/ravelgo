import 'package:flutter/material.dart';
import 'package:ravelgo_user/views/Driver_Portal/side_menu_driver.dart';

class ContactUsScreen extends StatelessWidget {
  const ContactUsScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const SideMenuDriver(initialSelectedItem: "Contacts",),
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
                "Contact Us",
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
              ),

              const SizedBox(height: 20),

              /// FORM CARD
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFFF7F7F7),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black12.withOpacity(0.05),
                        blurRadius: 6)
                  ],
                ),
                child: Column(
                  children: [
                    _inputField("Full Name"),
                    const SizedBox(height: 16),
                    _inputField("Email Address"),
                    const SizedBox(height: 16),
                    _inputField("Phone Number"),
                    const SizedBox(height: 16),
                    _inputField("Message", maxLines: 5),

                    const SizedBox(height: 24),

                    ElevatedButton(
                      onPressed: () {},
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFFD500),
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 40, vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text(
                        "Submit",
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 28),

              /// CONTACT DETAILS
              Row(
                children: const [
                  Icon(Icons.email_outlined),
                  SizedBox(width: 12),
                  Text("ravelgo.com",
                      style: TextStyle(fontSize: 16)),
                ],
              ),

              const SizedBox(height: 18),

              Row(
                children: const [
                  Icon(Icons.phone_outlined),
                  SizedBox(width: 12),
                  Text("08033333333",
                      style: TextStyle(fontSize: 16)),
                ],
              ),

              const SizedBox(height: 30),

              /// SOCIAL ICONS
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Image.asset("assets/Whatsapp.png",width: 32,height: 32,),
                  const Icon(Icons.telegram, color: Colors.blue, size: 32),
                  const Icon(Icons.facebook, color: Colors.blue, size: 32),
                  Image.asset("assets/Linkdin.png",width: 32,height: 32,),
                ],
              ),

              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  Widget _inputField(String hint, {int maxLines = 1}) {
    return TextField(
      maxLines: maxLines,
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        contentPadding:
        const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
    );
  }
}