import 'package:flutter/material.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';
import 'package:ravelgo_driver_app/views/auth/add_photo_screen.dart';

class CreateAccountScreen extends StatelessWidget {
  const CreateAccountScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppComponents.header(context, "Create driver account"),
              const SizedBox(height: 12),
              const Text(
                "Let's get you set up to start earning with RavelGo",
                style: TextStyle(fontSize: 15, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 24),
              const TextField(decoration: InputDecoration(labelText: 'Full name', border: OutlineInputBorder())),
              const SizedBox(height: 16),
              const TextField(decoration: InputDecoration(labelText: 'Email', border: OutlineInputBorder())),
              const SizedBox(height: 16),
              const TextField(decoration: InputDecoration(labelText: 'Phone number', border: OutlineInputBorder())),
              const SizedBox(height: 16),
              const TextField(
                obscureText: true,
                decoration: InputDecoration(labelText: 'Password', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 28),
              AppComponents.primaryButton(
                text: "Continue",
                onPressed: () {
                  Navigator.push(context, MaterialPageRoute(builder: (context) => const AddPhotoScreen()));
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
