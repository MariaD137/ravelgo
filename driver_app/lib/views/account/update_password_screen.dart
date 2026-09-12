import 'package:flutter/material.dart';
import 'package:ravelgo_driver_app/services/auth_service.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';

class UpdatePasswordScreen extends StatefulWidget {
  const UpdatePasswordScreen({super.key});

  @override
  State<UpdatePasswordScreen> createState() => _UpdatePasswordScreenState();
}

class _UpdatePasswordScreenState extends State<UpdatePasswordScreen> {
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _saving = false;
  String? _currentError;
  String? _newError;
  String? _confirmError;

  static final _strongPassword = RegExp(r'^(?=.*[a-z])(?=.*[A-Z])(?=.*\d).{8,}$');

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _currentError = _currentPasswordController.text.isEmpty ? 'Enter your current password' : null;
      _newError = !_strongPassword.hasMatch(_newPasswordController.text)
          ? 'Password must be 8+ chars with an uppercase, a lowercase, and a number.'
          : null;
      _confirmError =
          _confirmPasswordController.text != _newPasswordController.text ? 'Passwords do not match' : null;
    });
    if (_currentError != null || _newError != null || _confirmError != null) return;

    setState(() => _saving = true);
    try {
      await AuthService.changePassword(
        oldPassword: _currentPasswordController.text,
        newPassword: _newPasswordController.text,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Update password')),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: ListView(
          children: [
            const SizedBox(height: 20),
            _label('Current password'),
            _field(
              controller: _currentPasswordController,
              obscure: _obscureCurrent,
              error: _currentError,
              toggle: () => setState(() => _obscureCurrent = !_obscureCurrent),
            ),
            const SizedBox(height: 20),
            _label('New password'),
            _field(
              controller: _newPasswordController,
              obscure: _obscureNew,
              error: _newError,
              toggle: () => setState(() => _obscureNew = !_obscureNew),
            ),
            const SizedBox(height: 20),
            _label('Confirm password'),
            _field(
              controller: _confirmPasswordController,
              obscure: _obscureConfirm,
              error: _confirmError,
              toggle: () => setState(() => _obscureConfirm = !_obscureConfirm),
            ),
            const SizedBox(height: 32),
            AppComponents.primaryButton(
              text: _saving ? 'Saving…' : 'Save changes',
              onPressed: _saving ? null : _save,
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text, style: AppTypography.label.copyWith(color: AppColors.textPrimary)),
      );

  Widget _field({
    required TextEditingController controller,
    required bool obscure,
    String? error,
    required VoidCallback toggle,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      decoration: InputDecoration(
        errorText: error,
        prefixIcon: const Icon(Icons.lock_outline),
        suffixIcon: IconButton(
          icon: Icon(obscure ? Icons.visibility_off : Icons.visibility),
          onPressed: toggle,
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.medium)),
      ),
    );
  }
}
