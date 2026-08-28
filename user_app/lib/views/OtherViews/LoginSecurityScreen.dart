import 'package:flutter/material.dart';
import 'package:ravelgo_user_app/views/OtherViews/UpdatePassword.dart';
import 'package:ravelgo_user_app/theme/app_theme.dart';

class LoginSecurityScreen extends StatelessWidget {
  const LoginSecurityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        leading: const BackButton(color: AppColors.textPrimary),
        backgroundColor: AppColors.surface,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          "Login & Security",
          style: TextStyle(color: AppColors.textPrimary),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.password_outlined),
              title: const Text("Change password", style: TextStyle(fontSize: 16)),
              trailing: const Icon(Icons.chevron_right, color: AppColors.textSecondary),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const UpdatePassword()),
                );
              },
            ),
            const Divider(),
            const SizedBox(height: 20),
            const Text(
              "Linking a social account enables you to sign in to Ravel Go without using your phone number. "
                  "Your social account will only be used for login purposes, and we will not access or share any information without your consent.",
              style: TextStyle(color: AppColors.textPrimary, height: 1.5),
            ),
            const SizedBox(height: 30),
            _buildSocialRow('Apple', 'assets/apple_icon.png'),
            const Divider(),
            _buildSocialRow('Google', 'assets/google_icon.png'),
            const Divider(),
            _buildSocialRow('Facebook', 'assets/facebook_icon.png'),
            const Divider(),
          ],
        ),
      ),
    );
  }

  Widget _buildSocialRow(String label, String assetPath) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Image.asset(assetPath, height: 24, width: 24),
      title: Text(label, style: const TextStyle(fontSize: 16)),
      trailing: const Text(
        "Link",
        style: TextStyle(
          color: Colors.green,
          fontWeight: FontWeight.normal,
          fontSize: 16,
        ),
      ),
      onTap: () {
        // Handle link logic
      },
    );
  }
}