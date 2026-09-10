import 'package:flutter/material.dart';
import 'package:ravelgo_admin/services/admin_api.dart';
import 'package:ravelgo_admin/services/api_client.dart';
import 'package:ravelgo_admin/theme/app_theme.dart';
import 'package:ravelgo_admin/utils/date_utils.dart';

const _roleLabels = {
  'SUPER_ADMIN': 'Super Admin',
  'OPERATIONS_MANAGER': 'Operations Manager',
  'SUPPORT_AGENT': 'Support Agent',
  'FINANCE_VIEWER': 'Finance Viewer',
};

const _roleDescriptions = {
  'SUPER_ADMIN':
      'Full access to everything, including managing other admin users.',
  'OPERATIONS_MANAGER':
      'Drivers, pricing & surge. No payouts, no admin-user management.',
  'SUPPORT_AGENT':
      'Riders and safety alerts. No payouts, pricing, or admin-user management.',
  'FINANCE_VIEWER':
      'Read-only: can view payouts and reports, cannot act on anything.',
};

/// One admin's full detail + every protected action, all real and backend-
/// enforced (this screen never assumes an action succeeded locally — every
/// button re-fetches the updated record on success). Pops `true` if
/// anything changed so the list screen behind it reloads.
class AdminUserDetailScreen extends StatefulWidget {
  final AdminUserAccount user;
  const AdminUserDetailScreen({super.key, required this.user});

  @override
  State<AdminUserDetailScreen> createState() => _AdminUserDetailScreenState();
}

class _AdminUserDetailScreenState extends State<AdminUserDetailScreen> {
  late AdminUserAccount _user = widget.user;
  bool _busy = false;

  Future<void> _run(
    Future<AdminUserAccount> Function() action, {
    required String success,
  }) async {
    setState(() => _busy = true);
    try {
      final updated = await action();
      if (!mounted) return;
      setState(() => _user = updated);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(success)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is ApiException ? e.message : e.toString())),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _changeRole(String newRole) async {
    if (newRole == _user.adminRole) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Change permission preset?'),
        content: Text(
          '${_user.name.isEmpty ? _user.email : _user.name} will become ${_roleLabels[newRole]}.\n\n${_roleDescriptions[newRole] ?? ''}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Change'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final id = _user.id;
    if (id == null) return;
    await _run(
      () => AdminApi.setAdminUserRole(id, newRole),
      success: 'Role updated',
    );
  }

  Future<void> _toggleSuspended() async {
    final suspend = !_user.suspended;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(suspend ? 'Disable this admin?' : 'Enable this admin?'),
        content: Text(
          suspend
              ? '${_user.name.isEmpty ? _user.email : _user.name} will be signed out immediately and unable to sign back in.'
              : '${_user.name.isEmpty ? _user.email : _user.name} will regain access.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: suspend
                ? ElevatedButton.styleFrom(backgroundColor: AppColors.danger)
                : null,
            onPressed: () => Navigator.pop(context, true),
            child: Text(suspend ? 'Disable' : 'Enable'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final id = _user.id;
    if (id == null) return;
    await _run(
      () => AdminApi.setAdminUserSuspended(id, suspend),
      success: suspend ? 'Admin disabled' : 'Admin enabled',
    );
  }

  Future<void> _resendInvitation() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Resend invitation?'),
        content: Text('A new invitation email will be sent to ${_user.email}.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Resend'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final id = _user.id;
    if (id == null) return;
    await _run(
      () => AdminApi.resendAdminInvitation(id),
      success: 'Invitation resent',
    );
  }

  Future<void> _requestPasswordReset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Send password reset?'),
        content: Text(
          '${_user.email} will be emailed a reset code and required to set a new password on next sign-in. You will never see their password.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Send reset'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final id = _user.id;
    if (id == null) return;
    await _run(
      () => AdminApi.requestAdminPasswordReset(id),
      success: 'Password reset email sent',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Admin details')),
      body: AbsorbPointer(
        absorbing: _busy,
        child: Opacity(
          opacity: _busy ? 0.6 : 1,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _user.name.isEmpty ? _user.email : _user.name,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _user.email,
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    AppComponents.badge(
                      _roleLabels[_user.adminRole] ?? _user.adminRole,
                      color: _user.adminRole == 'SUPER_ADMIN'
                          ? AppColors.primary
                          : AppColors.info,
                    ),
                    _statusBadge(_user.status),
                    _mfaBadge(_user.mfaEnabled),
                  ],
                ),
                const SizedBox(height: 24),
                _field('Account status', _statusLabel(_user.status)),
                _field(
                  'MFA status',
                  _user.mfaEnabled
                      ? 'Enabled (authenticator app)'
                      : 'Not enrolled',
                ),
                _field(
                  'Created',
                  _user.createdAt == null
                      ? '—'
                      : formatShortDate(_user.createdAt!),
                ),
                _field(
                  'Last active',
                  _user.lastLoginAt == null
                      ? 'Never signed in'
                      : formatFriendlyDate(_user.lastLoginAt!),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Permission preset',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: _user.adminRole,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                  ),
                  items: _roleLabels.entries
                      .map(
                        (e) => DropdownMenuItem(
                          value: e.key,
                          child: Text(e.value),
                        ),
                      )
                      .toList(),
                  onChanged: _busy
                      ? null
                      : (v) => v == null ? null : _changeRole(v),
                ),
                const SizedBox(height: 28),
                const Text(
                  'Actions',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                if (_user.status == 'INVITED')
                  AppComponents.outlineButton(
                    text: 'Resend invitation',
                    onPressed: _busy ? null : _resendInvitation,
                  ),
                if (_user.status == 'INVITED') const SizedBox(height: 10),
                AppComponents.outlineButton(
                  text: 'Send password reset',
                  onPressed: _busy ? null : _requestPasswordReset,
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _user.suspended
                          ? AppColors.success
                          : AppColors.danger,
                    ),
                    onPressed: _busy ? null : _toggleSuspended,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Text(
                        _user.suspended ? 'Enable admin' : 'Disable admin',
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontSize: 14.5)),
        ],
      ),
    );
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'INVITED':
        return 'Invited — hasn\'t signed in yet';
      case 'ACTIVE':
        return 'Active';
      case 'SUSPENDED':
        return 'Suspended';
      default:
        return 'Unknown';
    }
  }

  Widget _statusBadge(String status) {
    final color = switch (status) {
      'INVITED' => AppColors.warning,
      'ACTIVE' => AppColors.success,
      'SUSPENDED' => AppColors.danger,
      _ => AppColors.textMuted,
    };
    return AppComponents.badge(
      _statusLabel(status).split(' —').first,
      color: color,
    );
  }

  Widget _mfaBadge(bool enabled) => AppComponents.badge(
    enabled ? 'MFA enabled' : 'MFA not enrolled',
    color: enabled ? AppColors.info : AppColors.textMuted,
  );
}
