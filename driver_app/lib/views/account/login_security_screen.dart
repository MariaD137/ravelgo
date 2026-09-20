import 'package:flutter/material.dart';
import 'package:ravelgo_driver_app/models/driver_profile.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';
import 'package:ravelgo_driver_app/views/account/update_password_screen.dart';
import 'package:ravelgo_driver_app/widgets/app_page_route.dart';

/// Login & Security: change password, plus honest verification status for
/// the identity fields the app actually has (email from Cognito, phone from
/// the driver's own User row) — no fabricated KYC/ID-verification flow.
class LoginSecurityScreen extends StatelessWidget {
  final DriverProfile profile;
  const LoginSecurityScreen({super.key, required this.profile});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Login & Security')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              decoration: AppComponents.cardDecoration(),
              child: AppComponents.tile(
                title: 'Change password',
                leading: Icons.password_outlined,
                onTap: () => Navigator.push(
                  context,
                  AppPageRoute(builder: (_) => const UpdatePasswordScreen()),
                ),
              ),
            ),
            const SizedBox(height: 16),
            AppComponents.sectionTitle('Verification'),
            Container(
              decoration: AppComponents.cardDecoration(),
              child: Column(
                children: [
                  _verificationRow(
                    icon: Icons.email_outlined,
                    label: profile.email.isNotEmpty ? profile.email : 'Email',
                    verified: profile.email.isNotEmpty,
                  ),
                  AppComponents.divider(),
                  _verificationRow(
                    icon: Icons.phone_outlined,
                    label: profile.phoneNumber.isNotEmpty ? profile.phoneNumber : 'Phone number',
                    verified: false,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _verificationRow({required IconData icon, required String label, required bool verified}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.base),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.textSecondary),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(label, style: AppTypography.cardTitle.copyWith(color: AppColors.textPrimary)),
          ),
          Text(
            verified ? 'Verified' : 'Not verified',
            style: AppTypography.label.copyWith(color: verified ? AppColors.success : AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}
