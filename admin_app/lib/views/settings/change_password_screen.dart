import 'package:flutter/material.dart';
import 'package:ravelgo_admin/services/auth_service.dart';
import 'package:ravelgo_admin/theme/app_theme.dart';

/// Admin password change, wired to Cognito (requires the admin to be signed in).
class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _currentController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _saving = false;
  String? _currentError;
  String? _newError;
  String? _confirmError;

  static final _strongPassword = RegExp(r'^(?=.*[a-z])(?=.*[A-Z])(?=.*\d).{8,}$');

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _currentError = _currentController.text.isEmpty ? 'Enter your current password' : null;
      _newError = !_strongPassword.hasMatch(_newController.text)
          ? 'Password must be 8+ chars with an uppercase, a lowercase, and a number.'
          : null;
      _confirmError = _confirmController.text != _newController.text ? 'Passwords do not match' : null;
    });
    if (_currentError != null || _newError != null || _confirmError != null) return;

    setState(() => _saving = true);
    try {
      await AuthService.changePassword(
        oldPassword: _currentController.text,
        newPassword: _newController.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Password changed.')));
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _currentError = AuthService.friendlyError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _field(String label, TextEditingController controller, String? error) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          obscureText: true,
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            errorText: error,
            prefixIcon: const Icon(Icons.lock_outline),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Change password')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _field('Current password', _currentController, _currentError),
            const SizedBox(height: 16),
            _field('New password', _newController, _newError),
            const SizedBox(height: 16),
            _field('Confirm new password', _confirmController, _confirmError),
            const SizedBox(height: 24),
            AppComponents.primaryButton(text: _saving ? 'Saving…' : 'Save changes', onPressed: _saving ? null : _save),
          ],
        ),
      ),
    );
  }
}
