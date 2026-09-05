import 'package:flutter/material.dart';
import 'package:ravelgo_admin/theme/app_theme.dart';

/// Honest placeholder: there is no staff/role-management backend in
/// RavelGo. Every admin endpoint checks a single Cognito group ("Admin") via
/// requireRole("Admin") - there's no concept of finer-grained roles
/// (Operations Manager, Support Agent, etc.) or a directory of staff members
/// to fabricate here. Access is granted/revoked directly in AWS Cognito.
class AdminRolesScreen extends StatelessWidget {
  const AdminRolesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Admin Roles")),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: AppComponents.cardDecoration(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: const [
                    Icon(Icons.info_outline, color: AppColors.textSecondary),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text("Role management isn't built yet", style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  "RavelGo doesn't have a staff directory or fine-grained roles "
                  "(e.g. \"Operations Manager\", \"Support Agent\"). Every admin "
                  "action in this app is gated on a single check: does the signed-in "
                  "user belong to the \"Admin\" group in AWS Cognito?",
                  style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 12),
                const Text(
                  "To grant or remove admin access, add or remove the user from the "
                  "Admin group in the Cognito user pool directly - there's no in-app "
                  "control for this, and building a fake one here would be misleading "
                  "about what's actually enforced.",
                  style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
