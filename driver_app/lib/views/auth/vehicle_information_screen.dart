import 'package:flutter/material.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';
import 'package:ravelgo_driver_app/views/auth/verify_account_screen.dart';

class VehicleInformationScreen extends StatelessWidget {
  const VehicleInformationScreen({super.key});

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
              AppComponents.header(context, "Vehicle information"),
              const SizedBox(height: 20),
              const TextField(decoration: InputDecoration(labelText: "Brand", border: OutlineInputBorder())),
              const SizedBox(height: 16),
              const TextField(decoration: InputDecoration(labelText: "Model", border: OutlineInputBorder())),
              const SizedBox(height: 16),
              const TextField(decoration: InputDecoration(labelText: "Colour", border: OutlineInputBorder())),
              const SizedBox(height: 16),
              const TextField(decoration: InputDecoration(labelText: "Plate number", border: OutlineInputBorder())),
              const SizedBox(height: 16),
              const TextField(decoration: InputDecoration(labelText: "Year", border: OutlineInputBorder())),
              const SizedBox(height: 24),
              AppComponents.uploadBox("Upload vehicle registration (Car Papers)"),
              const SizedBox(height: 12),
              AppComponents.uploadBox("Upload roadworthiness certificate"),
              const SizedBox(height: 12),
              AppComponents.uploadBox("Upload insurance certificate"),
              const SizedBox(height: 28),
              AppComponents.primaryButton(
                text: "Continue",
                onPressed: () {
                  Navigator.push(context, MaterialPageRoute(builder: (context) => const VerifyAccountScreen()));
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
