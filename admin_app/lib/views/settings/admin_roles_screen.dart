import 'package:flutter/material.dart';

/// Fine-grained admin roles (Super Admin / Ops Manager / Support Agent /
/// Finance Viewer, each scoped to a subset of modules) have no backend
/// representation yet — Cognito groups today are a single binary "Admin"
/// membership (see middleware/auth.ts's requireRole), and there is no
/// Prisma model for a permissions/role table. Building real fine-grained
/// admin RBAC means either Cognito custom groups/claims or a new
/// authorization layer — both out of scope until Cognito is configured.
/// This screen intentionally shows that honestly rather than a list of
/// invented roles and staff names with no backing data.
class AdminRolesScreen extends StatelessWidget {
  const AdminRolesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Admin Roles")),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.admin_panel_settings_outlined, size: 48, color: Colors.black38),
            const SizedBox(height: 16),
            const Text(
              "Fine-grained admin roles aren't available yet",
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              "Every signed-in admin currently has full access — RavelGo's Cognito "
              "setup has a single Admin group with no sub-roles yet. Scoped roles "
              "(Support Agent, Finance Viewer, etc.) will land once Cognito custom "
              "groups or an equivalent permissions model is configured.",
              style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
