import 'package:flutter/material.dart';
import 'package:ravelgo_admin/theme/app_theme.dart';

class AdminProfileScreen extends StatelessWidget {
  const AdminProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("My Profile")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _lockedField("Name", "Ops Admin"),
            const SizedBox(height: 16),
            _lockedField("Email", "admin@ravelgo.com"),
            const SizedBox(height: 16),
            _lockedField("Role", "Super Admin"),
            const SizedBox(height: 24),
            AppComponents.outlineButton(text: "Change password", onPressed: () {}),
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
