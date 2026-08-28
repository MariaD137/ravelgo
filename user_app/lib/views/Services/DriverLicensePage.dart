
import 'package:flutter/material.dart';
import 'package:ravelgo_user_app/components/basic_components.dart';
class DriverLicensePage extends StatelessWidget {
  const DriverLicensePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              AppComponents.header(context, "Drivers license"),
              const SizedBox(height: 10),

              AppComponents.label("Driver licence number"),
              AppComponents.label("A5678888"),

              const SizedBox(height: 16),

              AppComponents.UploadSection("Upload front of driver’s license"),
              const SizedBox(height: 12),
              AppComponents.UploadSection("Upload back of driver’s license"),

              const SizedBox(height: 16),

              AppComponents.label("Date of expiration"),
              AppComponents.inputField(hint: "27-02-2026"),


              const SizedBox(height: 16),

              AppComponents.label("Enter vehicle number"),
              AppComponents.inputField(hint: "A543527"),

              const SizedBox(height: 4),

              const Text(
                "if vehicle would be used for delivery",
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),

              const SizedBox(height: 20),

              AppComponents.disabledButton("Done"),
            ],
          ),
        ),
      ),
    );
  }
}