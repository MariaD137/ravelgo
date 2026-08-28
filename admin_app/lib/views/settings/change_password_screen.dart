import 'package:flutter/material.dart';
import 'package:ravelgo_admin/theme/app_theme.dart';

/// Admin password change.
/// AUTH BOUNDARY: no authentication backend is connected, so the password
/// cannot actually be changed. Input is fully validated and the submit
/// action states the boundary honestly - it never claims the password was
/// changed. `_save` is the integration point for the auth service.
class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _currentController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();
  String? _currentError;
  String? _newError;
  String? _confirmError;

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _save() {
    setState(() {
      _currentError = _currentController.text.isEmpty ? 'Enter your current password' : null;
      _newError = _newController.text.length < 8
          ? 'New password must be at least 8 characters'
          : null;
      _confirmError =
          _confirmController.text != _newController.text ? 'Passwords do not match' : null;
    });
    if (_currentError != null || _newError != null || _confirmError != null) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Not available yet'),
        content: const Text(
            'Password changes require the authentication service, which is not connected '
            'in this build. Your password has not been changed.'),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
      ),
    );
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
            AppComponents.primaryButton(text: 'Save changes', onPressed: _save),
          ],
        ),
      ),
    );
  }
}
