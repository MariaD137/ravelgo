import 'package:flutter/material.dart';
import 'package:ravelgo_admin/services/auth_service.dart';
import 'package:ravelgo_admin/theme/app_theme.dart';
import 'package:ravelgo_admin/views/shell/admin_shell.dart';

/// Shown when signIn() reports Cognito's NEW_PASSWORD_REQUIRED challenge —
/// every admin invited via POST /admin-users lands here on their first sign-in
/// with the temporary password Cognito emailed them.
class SetNewPasswordScreen extends StatefulWidget {
  final String email;
  const SetNewPasswordScreen({super.key, required this.email});

  @override
  State<SetNewPasswordScreen> createState() => _SetNewPasswordScreenState();
}

class _SetNewPasswordScreenState extends State<SetNewPasswordScreen> {
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _obscure = true;
  bool _loading = false;
  String? _error;

  static final _strongPassword = RegExp(r'^(?=.*[a-z])(?=.*[A-Z])(?=.*\d).{8,}$');

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final password = _passwordController.text;
    if (!_strongPassword.hasMatch(password)) {
      setState(() => _error = 'Password must be 8+ characters with an uppercase, a lowercase, and a number.');
      return;
    }
    if (password != _confirmController.text) {
      setState(() => _error = 'Passwords don\'t match.');
      return;
    }
    setState(() {
      _error = null;
      _loading = true;
    });
    try {
      await AuthService.completeNewPassword(newPassword: password);
      if (!AuthService.isAdmin) {
        await AuthService.signOut();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('You are not authorized to access the RavelGo Admin Console.'),
        ));
        Navigator.of(context).pop();
        return;
      }
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const AdminShell()),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = AuthService.friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Set a new password', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              'Welcome, ${widget.email}. This is your first sign-in — choose a permanent password to replace the temporary one.',
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _passwordController,
              obscureText: _obscure,
              decoration: InputDecoration(
                labelText: 'New password',
                suffixIcon: IconButton(
                  icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _confirmController,
              obscureText: _obscure,
              decoration: const InputDecoration(labelText: 'Confirm new password'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: AppColors.danger)),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _loading ? null : _submit,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: _loading
                      ? const SizedBox(
                          height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Set password and sign in'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
