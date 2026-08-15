import 'package:flutter/material.dart';
import 'package:ravelgo_driver_app/services/api_client.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _profileData = {};

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final response = await ApiClient().get('/drivers/me');
      if (!mounted) return;
      setState(() {
        _profileData = Map<String, dynamic>.from(response);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  String _field(String key, [String fallback = '']) {
    // Try top-level first, then check nested 'user' object
    if (_profileData.containsKey(key)) return _profileData[key]?.toString() ?? fallback;
    final user = _profileData['user'];
    if (user is Map && user.containsKey(key)) return user[key]?.toString() ?? fallback;
    return fallback;
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
                        Text('Failed to load profile', style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        Text(_error!, style: const TextStyle(fontSize: 12, color: Colors.black54), textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        AppComponents.outlineButton(text: "Retry", onPressed: () { setState(() { _loading = true; _error = null; }); _loadProfile(); }),
                      ],
                    ),
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Check and update your driver profile details here if needed", style: TextStyle(fontSize: 14, color: Colors.black54)),
                      const SizedBox(height: 24),
                      _lockedField("First Name", _field('firstName', '--')),
                      const SizedBox(height: 16),
                      _lockedField("Last Name", _field('lastName', '--')),
                      const SizedBox(height: 16),
                      _lockedField("Email", _field('email', '--')),
                      const SizedBox(height: 16),
                      _lockedField("Phone Number", _field('phoneNumber', '--')),
                      const SizedBox(height: 16),
                      _lockedField("Preferred Language", _field('preferredLanguage', '--')),
                      const SizedBox(height: 20),
                      const Text("To update, please contact our support team via the app", style: TextStyle(fontSize: 13, color: Colors.black54)),
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
