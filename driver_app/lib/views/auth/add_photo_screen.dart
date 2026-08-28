import 'package:flutter/material.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';
import 'package:ravelgo_driver_app/views/auth/driver_information_screen.dart';

class AddPhotoScreen extends StatelessWidget {
  const AddPhotoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
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
                    const CircleAvatar(radius: 60, backgroundColor: AppColors.surfaceElevated, child: Icon(Icons.person, size: 60, color: AppColors.textMuted)),
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
                  style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                ),
              ),
              const Spacer(),
              AppComponents.primaryButton(
                text: "Continue",
                onPressed: () {
                  Navigator.push(context, MaterialPageRoute(builder: (context) => const DriverInformationScreen()));
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
