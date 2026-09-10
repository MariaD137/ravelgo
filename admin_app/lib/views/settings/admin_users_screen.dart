import 'package:flutter/material.dart';
import 'package:ravelgo_admin/services/admin_api.dart';
import 'package:ravelgo_admin/services/api_client.dart';
import 'package:ravelgo_admin/theme/app_theme.dart';
import 'package:ravelgo_admin/utils/date_utils.dart';
import 'package:ravelgo_admin/views/settings/admin_user_detail_screen.dart';

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

/// Real admin-user management: invite new admins (Cognito emails them a
/// temporary password — they choose their own; RavelGo never sees or stores
/// it) and assign one of four fixed permission presets, enforced
/// server-side by requireAdminPermission (see
/// backend/src/lib/admin-permissions.ts) on top of the base Cognito "Admin"
/// group check. This screen itself only works for a caller whose own preset
/// is Super Admin — the backend is what actually enforces that, this screen
/// just surfaces the 403 clearly instead of pretending to work.
class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  bool _loading = true;
  bool _inviting = false;
  String? _error;
  List<AdminUserAccount> _users = const [];

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
      final users = await AdminApi.adminUsers();
      if (!mounted) return;
      setState(() {
        _users = users;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException && e.statusCode == 403
            ? 'You need Super Admin access to manage admin users.'
            : e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _openDetail(AdminUserAccount u) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AdminUserDetailScreen(user: u)),
    );
    // The detail screen may have changed role/status/invitation state —
    // always reload rather than trust a locally-fabricated merge.
    if (mounted) _load();
  }

  Future<void> _invite() async {
    final emailController = TextEditingController();
    final firstController = TextEditingController();
    final lastController = TextEditingController();
    String role = 'SUPPORT_AGENT';
    String? formError;

    final created = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          Future<void> submit() async {
            final email = emailController.text.trim();
            final first = firstController.text.trim();
            final last = lastController.text.trim();
            final emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
            if (first.isEmpty || last.isEmpty) {
              setDialogState(() => formError = 'Enter a first and last name.');
              return;
            }
            if (!emailPattern.hasMatch(email)) {
              setDialogState(() => formError = 'Enter a valid email address.');
              return;
            }
            setDialogState(() {
              formError = null;
              _inviting = true;
            });
            try {
              await AdminApi.createAdminUser(
                email: email,
                firstName: first,
                lastName: last,
                adminRole: role,
              );
              if (context.mounted) Navigator.pop(context, true);
            } catch (e) {
              setDialogState(() {
                _inviting = false;
                formError = e is ApiException ? e.message : e.toString();
              });
            }
          }

          return AlertDialog(
            title: const Text('Invite an admin user'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: firstController,
                    enabled: !_inviting,
                    decoration: const InputDecoration(labelText: 'First name'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: lastController,
                    enabled: !_inviting,
                    decoration: const InputDecoration(labelText: 'Last name'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: emailController,
                    enabled: !_inviting,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'Email'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: role,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Permission preset',
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
                    onChanged: _inviting
                        ? null
                        : (v) => setDialogState(() => role = v ?? role),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _roleDescriptions[role] ?? '',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'They\'ll get an email from AWS Cognito with a temporary password and set their own permanent one on first sign-in. Two-factor authentication is required before their account becomes fully active.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  if (formError != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      formError!,
                      style: const TextStyle(
                        color: AppColors.danger,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: _inviting
                    ? null
                    : () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: _inviting ? null : submit,
                child: _inviting
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Send invite'),
              ),
            ],
          );
        },
      ),
    );
    _inviting = false;
    if (created != true || !mounted) return;
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invite sent')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Admin Users"),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_alt_1_outlined),
            onPressed: _invite,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (_error != null ? _err() : _list()),
    );
  }

  Widget _err() => Center(
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
          TextButton(onPressed: _load, child: const Text('Try again')),
        ],
      ),
    ),
  );

  Widget _list() {
    if (_users.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.admin_panel_settings_outlined,
                size: 40,
                color: AppColors.textMuted,
              ),
              const SizedBox(height: 12),
              const Text(
                "No admin users yet.",
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              const Text(
                "Tap the + icon to invite your first admin.",
                style: TextStyle(color: AppColors.textSecondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _invite,
                icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
                label: const Text('Invite an admin'),
              ),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _users.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          final u = _users[i];
          return InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _openDetail(u),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: AppComponents.cardDecoration(),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          u.name.isEmpty ? u.email : u.name,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          u.email,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            AppComponents.badge(
                              _roleLabels[u.adminRole] ?? u.adminRole,
                              color: u.adminRole == 'SUPER_ADMIN'
                                  ? AppColors.primary
                                  : AppColors.info,
                            ),
                            _statusBadge(u.status),
                            if (u.mfaEnabled)
                              AppComponents.badge('MFA', color: AppColors.info)
                            else
                              AppComponents.badge(
                                'No MFA',
                                color: AppColors.textMuted,
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          u.lastLoginAt == null
                              ? 'Never signed in · Joined ${u.createdAt == null ? '—' : formatShortDate(u.createdAt!)}'
                              : 'Last active ${formatFriendlyDate(u.lastLoginAt!)}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _statusBadge(String status) {
    final color = switch (status) {
      'INVITED' => AppColors.warning,
      'ACTIVE' => AppColors.success,
      'SUSPENDED' => AppColors.danger,
      _ => AppColors.textMuted,
    };
    final label = switch (status) {
      'INVITED' => 'Invited',
      'ACTIVE' => 'Active',
      'SUSPENDED' => 'Suspended',
      _ => 'Unknown',
    };
    return AppComponents.badge(label, color: color);
  }
}
