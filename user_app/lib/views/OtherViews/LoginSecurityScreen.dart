import 'package:flutter/material.dart';
import 'package:ravelgo_user_app/services/rider_api.dart';
import 'package:ravelgo_user_app/views/OtherViews/UpdatePassword.dart';
import 'package:ravelgo_user_app/theme/app_theme.dart';

class LoginSecurityScreen extends StatefulWidget {
  const LoginSecurityScreen({super.key});

  @override
  State<LoginSecurityScreen> createState() => _LoginSecurityScreenState();
}

class _LoginSecurityScreenState extends State<LoginSecurityScreen> {
  bool _loading = true;
  String? _email;
  String? _phoneNumber;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final me = await RiderApi.getMe();
      if (!mounted) return;
      setState(() {
        _email = me?['email']?.toString();
        _phoneNumber = me?['phoneNumber']?.toString();
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

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
              "Verification",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 8),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              _verificationRow(
                icon: Icons.email_outlined,
                label: _email?.isNotEmpty == true ? _email! : 'Email',
                verified: _email?.isNotEmpty == true,
              ),
              const Divider(),
              _verificationRow(
                icon: Icons.phone_outlined,
                label: _phoneNumber?.isNotEmpty == true ? _phoneNumber! : 'Phone number',
                verified: false,
              ),
            ],
            const Divider(),
            const SizedBox(height: 20),
            const Text(
              "Linking a social account enables you to sign in to Ravel Go without using your phone number. "
                  "Your social account will only be used for login purposes, and we will not access or share any information without your consent.",
              style: TextStyle(color: AppColors.textPrimary, height: 1.5),
            ),
            const SizedBox(height: 30),
            _buildSocialRow(context, 'Apple', 'assets/apple_icon.png'),
            const Divider(),
            _buildSocialRow(context, 'Google', 'assets/google_icon.png'),
            const Divider(),
            _buildSocialRow(context, 'Facebook', 'assets/facebook_icon.png'),
            const Divider(),
          ],
        ),
      ),
    );
  }

  Widget _verificationRow({required IconData icon, required String label, required bool verified}) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: AppColors.textSecondary),
      title: Text(label, style: const TextStyle(fontSize: 16)),
      trailing: Text(
        verified ? 'Verified' : 'Not verified',
        style: TextStyle(
          color: verified ? AppColors.success : AppColors.textSecondary,
          fontWeight: FontWeight.w600,
          fontSize: 14,
        ),
      ),
    );
  }

  Widget _buildSocialRow(BuildContext context, String label, String assetPath) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Image.asset(assetPath, height: 24, width: 24),
      title: Text(label, style: const TextStyle(fontSize: 16)),
      trailing: const Text(
        "Link",
        style: TextStyle(
          color: AppColors.success,
          fontWeight: FontWeight.normal,
          fontSize: 16,
        ),
      ),
      onTap: () {
        // AUTH BOUNDARY: social sign-in providers are not configured in this
        // build, so linking cannot actually happen - say so instead of
        // silently doing nothing.
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('$label sign-in is not configured in this build yet'),
        ));
      },
    );
  }
}