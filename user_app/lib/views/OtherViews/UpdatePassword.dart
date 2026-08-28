import 'package:flutter/material.dart';
import 'package:ravelgo_user_app/theme/app_theme.dart';

class UpdatePassword extends StatefulWidget {
  const UpdatePassword({super.key});

  @override
  State<UpdatePassword> createState() => _UpdatePasswordState();
}

class _UpdatePasswordState extends State<UpdatePassword> {
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  String? _currentError;
  String? _newError;
  String? _confirmError;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        leading: const BackButton(color: AppColors.textPrimary),
        backgroundColor: AppColors.surface,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          "Update password",
          style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w500),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: ListView(
          children: [
            const SizedBox(height: 20),
            _buildLabel("Current Password"),
            _buildPasswordField(
              controller: _currentPasswordController,
              obscure: _obscureCurrent,
              error: _currentError,
              toggle: () => setState(() => _obscureCurrent = !_obscureCurrent),
            ),
            const SizedBox(height: 20),
            _buildLabel("New Password"),
            _buildPasswordField(
              controller: _newPasswordController,
              obscure: _obscureNew,
              error: _newError,
              toggle: () => setState(() => _obscureNew = !_obscureNew),
            ),
            const SizedBox(height: 20),
            _buildLabel("Confirm Password"),
            _buildPasswordField(
              controller: _confirmPasswordController,
              obscure: _obscureConfirm,
              error: _confirmError,
              toggle: () => setState(() => _obscureConfirm = !_obscureConfirm),
            ),
            const SizedBox(height: 40),
            _buildSaveButton(),
          ],
        ),
      ),
    );
  }

  /// Validates locally, then hits the auth boundary.
  /// AUTH BOUNDARY: no authentication backend is connected, so the password
  /// cannot actually be changed; the user is told so instead of a fake
  /// success message. This method is the integration point.
  void _save() {
    setState(() {
      _currentError =
          _currentPasswordController.text.isEmpty ? 'Enter your current password' : null;
      _newError = _newPasswordController.text.length < 6
          ? 'New password must be at least 6 characters'
          : null;
      _confirmError = _confirmPasswordController.text != _newPasswordController.text
          ? 'Passwords do not match'
          : null;
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

  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.w500)),
    );
  }

  Widget _buildPasswordField({
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
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  Widget _buildSaveButton() {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.textPrimary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        onPressed: _save,
        child: const Text("Save Changes"),
      ),
    );
  }
}