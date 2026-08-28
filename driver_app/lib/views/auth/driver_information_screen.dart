import 'package:flutter/material.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';
import 'package:ravelgo_driver_app/views/auth/vehicle_information_screen.dart';

class DriverInformationScreen extends StatelessWidget {
  const DriverInformationScreen({super.key});

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
              AppComponents.header(context, "Driver information"),
              const SizedBox(height: 12),
              const Text(
                "This information is used for the Driver Matching Algorithm to pair you with the right riders",
                style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 24),
              const TextField(decoration: InputDecoration(labelText: "Driver's License Number", border: OutlineInputBorder())),
              const SizedBox(height: 16),
              const TextField(decoration: InputDecoration(labelText: "Years of driving experience", border: OutlineInputBorder())),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(labelText: "Preferred language", border: OutlineInputBorder()),
                items: const ["English", "French", "Yoruba", "Igbo", "Hausa"]
                    .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                    .toList(),
                onChanged: (_) {},
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text("Prefer quiet rides (no small talk)"),
                value: false,
                onChanged: (_) {},
              ),
              const SizedBox(height: 24),
              AppComponents.uploadBox("Upload driver's license"),
              const SizedBox(height: 12),
              AppComponents.uploadBox("Upload background check consent"),
              const SizedBox(height: 28),
              AppComponents.primaryButton(
                text: "Continue",
                onPressed: () {
                  Navigator.push(context, MaterialPageRoute(builder: (context) => const VehicleInformationScreen()));
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
