import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:ravelgo_admin/services/auth_service.dart';
import 'package:ravelgo_admin/theme/app_theme.dart';

class AdminProfileScreen extends StatefulWidget {
  const AdminProfileScreen({super.key});

  @override
  State<AdminProfileScreen> createState() => _AdminProfileScreenState();
}

class _AdminProfileScreenState extends State<AdminProfileScreen> {
  String _name = '';
  String _email = '';
  String _role = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final token = await AuthService().getAccessToken();
      if (token != null) {
        final parts = token.split('.');
        if (parts.length == 3) {
          final payload = jsonDecode(
            utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
          ) as Map<String, dynamic>;

          if (!mounted) return;
          setState(() {
            _name = payload['name'] as String? ??
                payload['cognito:username'] as String? ??
                payload['sub'] as String? ??
                'Admin';
            _email = payload['email'] as String? ?? '';
            _role = payload['custom:role'] as String? ??
                _extractRole(payload['cognito:groups']) ??
                'Admin';
            _loading = false;
          });
          return;
        }
      }
    } catch (_) {
      // Fall through to defaults
    }
    if (!mounted) return;
    setState(() {
      _name = 'Admin';
      _email = 'Not available';
      _role = 'Admin';
      _loading = false;
    });
  }

  String? _extractRole(dynamic groups) {
    if (groups == null) return null;
    if (groups is List && groups.isNotEmpty) return groups.first.toString();
    return groups.toString();
  }

  void _changePassword() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Change Password'),
        content: const Text(
          'To change your password, please contact your system administrator or use the password reset flow from the login screen.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text("My Profile")),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text("My Profile")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _lockedField("Name", _name),
            const SizedBox(height: 16),
            _lockedField("Email", _email),
            const SizedBox(height: 16),
            _lockedField("Role", _role),
            const SizedBox(height: 24),
            AppComponents.outlineButton(text: "Change password", onPressed: _changePassword),
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
