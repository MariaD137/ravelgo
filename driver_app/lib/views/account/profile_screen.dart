import 'package:flutter/material.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("My Profile")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Check and update your driver profile details here if needed", style: TextStyle(fontSize: 14, color: Colors.black54)),
            const SizedBox(height: 24),
            _lockedField("First Name", "Thelma"),
            const SizedBox(height: 16),
            _lockedField("Last Name", "Ibeh"),
            const SizedBox(height: 16),
            _lockedField("Email", "thelma123@gmail.com"),
            const SizedBox(height: 16),
            _lockedField("Phone Number", "07037530052"),
            const SizedBox(height: 16),
            _lockedField("In-App Profile Name", "Thelma Ibeh"),
            const SizedBox(height: 20),
            const Text("To update, please contact our support team via the app", style: TextStyle(fontSize: 13, color: Colors.black54)),
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
