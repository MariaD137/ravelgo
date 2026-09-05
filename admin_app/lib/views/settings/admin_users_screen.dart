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
  'SUPER_ADMIN': 'Full access to everything, including managing other admin users.',
  'OPERATIONS_MANAGER': 'Drivers, pricing & surge. No payouts, no admin-user management.',
  'SUPPORT_AGENT': 'Riders and safety alerts. No payouts, pricing, or admin-user management.',
  'FINANCE_VIEWER': 'Read-only: can view payouts and reports, cannot act on anything.',
};

/// Real admin-user management: invite new admins (Cognito emails them a
/// temporary password) and assign one of four fixed permission presets,
/// enforced server-side by requireAdminPermission (see
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
  bool _busy = false;
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

  Future<void> _invite() async {
    final emailController = TextEditingController();
    final firstController = TextEditingController();
    final lastController = TextEditingController();
    String role = 'SUPPORT_AGENT';

    final created = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Invite an admin user'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(controller: firstController, decoration: const InputDecoration(labelText: 'First name')),
                TextField(controller: lastController, decoration: const InputDecoration(labelText: 'Last name')),
                TextField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'Email')),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: role,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Permission preset', border: OutlineInputBorder()),
                  items: _roleLabels.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
                  onChanged: (v) => setDialogState(() => role = v ?? role),
                ),
                const SizedBox(height: 6),
                Text(_roleDescriptions[role] ?? '', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                const SizedBox(height: 10),
                const Text(
                  'They\'ll get an email from AWS Cognito with a temporary password and set their own permanent one on first sign-in.',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Send invite')),
          ],
        ),
      ),
    );
    if (created != true || !mounted) return;

    if (emailController.text.trim().isEmpty || firstController.text.trim().isEmpty || lastController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a first name, last name, and email')));
      return;
    }

    setState(() => _busy = true);
    try {
      await AdminApi.createAdminUser(
        email: emailController.text.trim(),
        firstName: firstController.text.trim(),
        lastName: lastController.text.trim(),
        adminRole: role,
      );
      await _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invite sent')));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e is ApiException ? e.message : e.toString())));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _changeRole(AdminUserAccount u, String newRole) async {
    if (newRole == u.adminRole) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Change permission preset?'),
        content: Text('${u.name.isEmpty ? u.email : u.name} will become ${_roleLabels[newRole]}.\n\n${_roleDescriptions[newRole] ?? ''}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Change')),
        ],
      ),
    );
    if (confirmed != true) return;
    await _run(() => AdminApi.setAdminUserRole(u.id, newRole), success: 'Role updated');
  }

  Future<void> _toggleSuspended(AdminUserAccount u) async {
    final suspend = !u.suspended;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(suspend ? 'Suspend this admin?' : 'Reinstate this admin?'),
        content: Text(suspend
            ? '${u.name.isEmpty ? u.email : u.name} will be signed out and unable to sign back in.'
            : '${u.name.isEmpty ? u.email : u.name} will regain access.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            style: suspend ? ElevatedButton.styleFrom(backgroundColor: AppColors.danger) : null,
            onPressed: () => Navigator.pop(context, true),
            child: Text(suspend ? 'Suspend' : 'Reinstate'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _run(() => AdminApi.setAdminUserSuspended(u.id, suspend), success: suspend ? 'Admin suspended' : 'Admin reinstated');
  }

  Future<void> _run(Future<void> Function() action, {required String success}) async {
    setState(() => _busy = true);
    try {
      await action();
      await _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(success)));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e is ApiException ? e.message : e.toString())));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Admin Users"),
        actions: [IconButton(icon: const Icon(Icons.person_add_alt_1_outlined), onPressed: _invite)],
      ),
      body: _loading ? const Center(child: CircularProgressIndicator()) : (_error != null ? _err() : _list()),
    );
  }

  Widget _err() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.danger)),
            TextButton(onPressed: _load, child: const Text('Try again')),
          ]),
        ),
      );

  Widget _list() {
    if (_users.isEmpty) {
      return const Center(child: Text("No admin users yet.", style: TextStyle(color: AppColors.textSecondary)));
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
          return Container(
            padding: const EdgeInsets.all(14),
            decoration: AppComponents.cardDecoration(),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(u.name.isEmpty ? u.email : u.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(u.email, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                      const SizedBox(height: 6),
                      Wrap(spacing: 6, runSpacing: 6, children: [
                        AppComponents.badge(_roleLabels[u.adminRole] ?? u.adminRole,
                            color: u.adminRole == 'SUPER_ADMIN' ? AppColors.primary : AppColors.info),
                        if (u.suspended) AppComponents.badge("Suspended", color: AppColors.danger),
                      ]),
                      const SizedBox(height: 2),
                      Text("Joined ${formatFriendlyDate(u.createdAt)}",
                          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  enabled: !_busy,
                  onSelected: (v) {
                    if (v == 'suspend') {
                      _toggleSuspended(u);
                    } else {
                      _changeRole(u, v);
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(enabled: false, child: Text('Set preset to:', style: TextStyle(fontWeight: FontWeight.w700))),
                    ..._roleLabels.entries.map((e) => PopupMenuItem(
                          value: e.key,
                          child: Row(children: [
                            if (e.key == u.adminRole) const Icon(Icons.check, size: 16),
                            if (e.key == u.adminRole) const SizedBox(width: 6),
                            Text(e.value),
                          ]),
                        )),
                    const PopupMenuDivider(),
                    PopupMenuItem(value: 'suspend', child: Text(u.suspended ? 'Reinstate' : 'Suspend')),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
