import 'package:flutter/material.dart';

import 'side_menu_driver.dart';

class RavelDriverPortalScreen extends StatelessWidget {
  const RavelDriverPortalScreen({Key? key}) : super(key: key);

  final InputDecoration _decoration = const InputDecoration(
    border: OutlineInputBorder(),
    contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 16),
    prefixIcon: Icon(Icons.lock_outline),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const SideMenuDriver(initialSelectedItem: "My Profile",),
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              /// Top Header
              Row(
                children: [
                  Builder(
                    builder: (context) {
                      return GestureDetector(
                        onTap: () {
                          Scaffold.of(context).openDrawer();
                        },
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
                      );
                    },
                  ),
                  const SizedBox(width: 16),
                  Image.asset(
                    "assets/ravel_go_driver_badge.png", // <-- your logo path
                    height: 28,
                    fit: BoxFit.contain,
                  ),
                ],
              ),

              const SizedBox(height: 28),

              /// Profile Title
              const Text(
                "Profile",
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              const Text(
                "Check and update your driver profile details here if needed",
                style: TextStyle(fontSize: 15, color: Colors.black54),
              ),

              const SizedBox(height: 28),

              /// First Name
              _label("First Name"),
              _lockedField("Thelma"),

              const SizedBox(height: 18),

              /// Last Name
              _label("Last Name"),
              _lockedField("Thelma Ibeh"),

              const SizedBox(height: 18),

              /// Email
              _label("Email"),
              _lockedField("thelma123@gmail.com"),
              _helperText(),

              const SizedBox(height: 18),

              /// Phone Number
              _label("Phone Number"),
              _lockedField("07037530052"),
              _helperText(),

              const SizedBox(height: 18),

              /// In-App Profile Name
              _label("In-App profile Name"),
              _lockedField("Thelma Ibeh"),
              _helperText(),
            ],
          ),
        ),
      ),
    );
  }

  /// Label Widget
  Widget _label(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    );
  }

  /// Locked Field
  Widget _lockedField(String value) {
    return TextField(
      readOnly: true,
      decoration: InputDecoration(
        hintText: value,
        border: const OutlineInputBorder(),
        contentPadding:
        const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        prefixIcon: const Icon(Icons.lock_outline),
      ),
    );
  }

  /// Helper text below fields
  Widget _helperText() {
    return const Padding(
      padding: EdgeInsets.only(top: 6),
      child: Text(
        "To update, please contact our support team via the app",
        style: TextStyle(fontSize: 13, color: Colors.black54),
      ),
    );
  }
}