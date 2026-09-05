import 'package:flutter/material.dart';
import 'package:ravelgo_driver_app/models/driver_profile.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';

class ProfileScreen extends StatelessWidget {
  final DriverProfile profile;
  const ProfileScreen({super.key, this.profile = const DriverProfile()});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("My Profile")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Check and update your driver profile details here if needed", style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
            const SizedBox(height: 24),
            _lockedField("First Name", profile.firstName),
            const SizedBox(height: 16),
            _lockedField("Last Name", profile.lastName.isNotEmpty ? profile.lastName : "Not provided"),
            const SizedBox(height: 16),
            _lockedField("Email", profile.email.isNotEmpty ? profile.email : "Not provided"),
            const SizedBox(height: 16),
            _lockedField("Phone Number", profile.phoneNumber.isNotEmpty ? profile.phoneNumber : "Not provided"),
            const SizedBox(height: 16),
            _lockedField("In-App Profile Name", profile.fullName.isNotEmpty ? profile.fullName : "Driver"),
            const SizedBox(height: 20),
            const Text("To update, please contact our support team via the app", style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }

  Widget _lockedField(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        TextField(
          readOnly: true,
          decoration: InputDecoration(
            hintText: value,
            border: const OutlineInputBorder(),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            prefixIcon: const Icon(Icons.lock_outline),
          ),
        ),
      ],
    );
  }
}
