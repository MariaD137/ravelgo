import 'package:flutter/material.dart';
import 'package:ravelgo_admin/services/admin_api.dart';
import 'package:ravelgo_admin/services/api_client.dart';
import 'package:ravelgo_admin/theme/app_theme.dart';
import 'package:ravelgo_admin/views/auth/mfa_setup_screen.dart';
import 'package:ravelgo_admin/views/settings/change_password_screen.dart';

const _roleLabels = {
  'SUPER_ADMIN': 'Super Admin',
  'OPERATIONS_MANAGER': 'Operations Manager',
  'SUPPORT_AGENT': 'Support Agent',
  'FINANCE_VIEWER': 'Finance Viewer',
};

/// The signed-in admin's own profile — real data from GET /admin-users/me
/// (see admin_api.dart), never hard-coded. Name/email/role/account status/
/// MFA status all come from the authenticated identity; there is nothing on
/// this screen a client could fabricate a value for.
class AdminProfileScreen extends StatefulWidget {
  const AdminProfileScreen({super.key});

  @override
  State<AdminProfileScreen> createState() => _AdminProfileScreenState();
}

class _AdminProfileScreenState extends State<AdminProfileScreen> {
  bool _loading = true;
  String? _error;
  AdminUserAccount? _me;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final me = await AdminApi.me();
      if (!mounted) return;
      setState(() {
        _me = me;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException ? e.message : e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("My Profile")),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.danger),
                    ),
                    TextButton(
                      onPressed: _load,
                      child: const Text('Try again'),
                    ),
                  ],
                ),
              ),
            )
          : _body(_me!),
    );
  }

  Widget _body(AdminUserAccount me) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _lockedField("Name", me.name.isEmpty ? '—' : me.name),
          const SizedBox(height: 16),
          _lockedField("Email", me.email),
          const SizedBox(height: 16),
          _lockedField("Role", _roleLabels[me.adminRole] ?? me.adminRole),
          const SizedBox(height: 16),
          _lockedField("Account status", switch (me.status) {
            'ACTIVE' => 'Active',
            'INVITED' => 'Invited',
            'SUSPENDED' => 'Suspended',
            _ => 'Unknown',
          }),
          const SizedBox(height: 16),
          _lockedField(
            "Two-factor authentication",
            me.mfaEnabled ? 'Enabled' : 'Not enrolled',
            icon: me.mfaEnabled
                ? Icons.verified_user_outlined
                : Icons.warning_amber_outlined,
          ),
          const SizedBox(height: 24),
          AppComponents.outlineButton(
            text: "Change password",
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ChangePasswordScreen()),
            ),
          ),
          if (!me.mfaEnabled) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const MfaSetupScreen()),
                  );
                  if (mounted) _load();
                },
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  child: Text("Set up two-factor authentication"),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _lockedField(
    String label,
    String value, {
    IconData icon = Icons.lock_outline,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        TextField(
          readOnly: true,
          controller: TextEditingController(text: value),
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 14,
            ),
            prefixIcon: Icon(icon),
          ),
        ),
      ],
    );
  }
}
