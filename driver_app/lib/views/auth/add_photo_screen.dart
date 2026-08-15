import 'package:flutter/material.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';
import 'package:ravelgo_driver_app/views/auth/driver_information_screen.dart';

class AddPhotoScreen extends StatelessWidget {
  final String email;
  const AddPhotoScreen({super.key, required this.email});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppComponents.header(context, "Add a profile photo"),
              const SizedBox(height: 24),
              Center(
                child: Stack(
                  children: [
                    const CircleAvatar(radius: 60, backgroundColor: Color(0xFFF0F0F0), child: Icon(Icons.person, size: 60, color: Colors.black26)),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                        child: const Icon(Icons.camera_alt, size: 18),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              const Center(
                child: Text(
                  "Riders will see this photo when matched with you",
                  style: TextStyle(fontSize: 13, color: Colors.black54),
                ),
              ),
              const Spacer(),
              AppComponents.primaryButton(
                text: "Continue",
                onPressed: () {
                  Navigator.push(context, MaterialPageRoute(builder: (context) => DriverInformationScreen(email: email)));
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
