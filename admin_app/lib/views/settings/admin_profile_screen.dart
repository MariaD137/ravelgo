import 'package:flutter/material.dart';
import 'package:ravelgo_admin/services/api/admin_api.dart';
import 'package:ravelgo_admin/services/api/api_client.dart';
import 'package:ravelgo_admin/theme/app_theme.dart';

class AdminProfileScreen extends StatefulWidget {
  final AdminApi? adminApi;
  const AdminProfileScreen({super.key, this.adminApi});

  @override
  State<AdminProfileScreen> createState() => _AdminProfileScreenState();
}

class _AdminProfileScreenState extends State<AdminProfileScreen> {
  late final AdminApi _api = widget.adminApi ?? AdminApi(ApiClient());
  Future<Map<String, dynamic>?>? _future;

  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>?> _load() async {
    try {
      return await _api.getMe();
    } on ApiException catch (err) {
      if (err.statusCode == 404) return null;
      rethrow;
    }
  }

  Future<void> _createProfile() async {
    if (_firstNameController.text.trim().isEmpty || _lastNameController.text.trim().isEmpty || _emailController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Fill in your name and email.')));
      return;
    }
    setState(() => _creating = true);
    try {
      await _api.createMe(
        firstName: _firstNameController.text.trim(),
        lastName: _lastNameController.text.trim(),
        email: _emailController.text.trim(),
      );
      if (!mounted) return;
      setState(() => _future = _load());
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to create profile: $err')));
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("My Profile")),
      body: FutureBuilder<Map<String, dynamic>?>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Failed to load profile: ${snapshot.error}'));
          }
          final admin = snapshot.data;
          if (admin == null) {
            // No Postgres row for this Cognito admin yet — same bootstrap
            // pattern drivers/riders go through on first sign-in.
            return SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Set up your admin profile", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  const SizedBox(height: 16),
                  TextField(controller: _firstNameController, decoration: const InputDecoration(labelText: "First name", border: OutlineInputBorder())),
                  const SizedBox(height: 12),
                  TextField(controller: _lastNameController, decoration: const InputDecoration(labelText: "Last name", border: OutlineInputBorder())),
                  const SizedBox(height: 12),
                  TextField(controller: _emailController, decoration: const InputDecoration(labelText: "Email", border: OutlineInputBorder())),
                  const SizedBox(height: 20),
                  AppComponents.primaryButton(text: _creating ? "Saving…" : "Save", onPressed: _creating ? null : _createProfile),
                ],
              ),
            );
          }
          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _lockedField("Name", "${admin['firstName']} ${admin['lastName']}"),
                const SizedBox(height: 16),
                _lockedField("Email", admin['email'] as String),
                const SizedBox(height: 16),
                _lockedField("Role", admin['role'] as String),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _lockedField(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(border: Border.all(color: Colors.black26), borderRadius: BorderRadius.circular(4)),
          child: Row(
            children: [
              const Icon(Icons.lock_outline, size: 20, color: Colors.black54),
              const SizedBox(width: 10),
              Text(value),
            ],
          ),
        ),
      ],
    );
  }
}
