import 'package:flutter/material.dart';
import 'package:ravelgo_driver_app/models/driver_onboarding_draft.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';
import 'package:ravelgo_driver_app/views/auth/driver_information_screen.dart';

// A profile photo has no backing field on the Driver/User model yet (no
// avatar/fileKey column, no upload endpoint for it) — this step stays
// decorative rather than wired to a fake upload, per the same
// don't-invent-backend-capability rule as the Ratings/Incentives screens.
// It still carries the onboarding draft forward untouched.
class AddPhotoScreen extends StatelessWidget {
  const AddPhotoScreen({super.key, required this.draft});

  final DriverOnboardingDraft draft;

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
                  Navigator.push(context, MaterialPageRoute(builder: (context) => DriverInformationScreen(draft: draft)));
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
