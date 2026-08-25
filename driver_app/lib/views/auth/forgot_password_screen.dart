import 'package:flutter/material.dart';
import 'package:ravelgo_driver_app/services/auth_service.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';

/// Two real Cognito steps, not a fake "check your email" dialog: request a
/// reset code (AuthService.forgotPassword), then submit that code with a
/// new password (AuthService.confirmForgotPassword). Never advances past a
/// step, or shows success, unless Cognito itself returned 200.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailController = TextEditingController();
  final _codeController = TextEditingController();
  final _newPasswordController = TextEditingController();

  // Step 1 = enter email, request a code. Step 2 = enter code + new
  // password. A separate _codeSentToEmail (not just a bool) so step 2 can
  // always show exactly which address the code went to, even if the user
  // edited the email field after requesting it.
  bool _codeRequested = false;
  String? _codeSentToEmail;
  bool _isLoading = false;
  String? _errorMessage;
  bool _passwordResetComplete = false;

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    _newPasswordController.dispose();
    super.dispose();
  }

  Future<void> _requestCode() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      setState(() => _errorMessage = 'Please enter your email');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final result = await AuthService().forgotPassword(email);

    if (!mounted) return;
    if (result['success'] == true) {
      setState(() {
        _isLoading = false;
        _codeRequested = true;
        _codeSentToEmail = email;
      });
    } else {
      setState(() {
        _isLoading = false;
        _errorMessage = result['error'] as String?;
      });
    }
  }

  Future<void> _confirmReset() async {
    final code = _codeController.text.trim();
    final newPassword = _newPasswordController.text;

    if (code.isEmpty || newPassword.isEmpty) {
      setState(() => _errorMessage = 'Please enter the code and a new password');
      return;
    }
    if (newPassword.length < 8) {
      setState(() => _errorMessage = 'Password must be at least 8 characters');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final result = await AuthService().confirmForgotPassword(_codeSentToEmail!, code, newPassword);

    if (!mounted) return;
    if (result['success'] == true) {
      setState(() {
        _isLoading = false;
        _passwordResetComplete = true;
      });
    } else {
      setState(() {
        _isLoading = false;
        _errorMessage = result['error'] as String?;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0, title: const Text('Reset password')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_passwordResetComplete) ...[
                  const Icon(Icons.check_circle, color: AppColors.success, size: 48),
                  const SizedBox(height: 16),
                  const Text('Password reset', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text(
                    'Your password has been changed. You can now sign in with your new password.',
                    style: TextStyle(fontSize: 14, color: Colors.black54),
                  ),
                  const SizedBox(height: 24),
                  AppComponents.primaryButton(
                    text: 'Back to sign in',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ] else if (!_codeRequested) ...[
                  const Text(
                    'Enter your email address and we\'ll send you a code to reset your password.',
                    style: TextStyle(fontSize: 14, color: Colors.black54),
                  ),
                  const SizedBox(height: 20),
                  if (_errorMessage != null) ...[
                    _ErrorBanner(_errorMessage!),
                    const SizedBox(height: 16),
                  ],
                  TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 20),
                  AppComponents.primaryButton(
                    text: _isLoading ? 'Sending...' : 'Send reset code',
                    onPressed: _isLoading ? null : _requestCode,
                  ),
                ] else ...[
                  Text(
                    'Enter the code sent to $_codeSentToEmail and choose a new password.',
                    style: const TextStyle(fontSize: 14, color: Colors.black54),
                  ),
                  const SizedBox(height: 20),
                  if (_errorMessage != null) ...[
                    _ErrorBanner(_errorMessage!),
                    const SizedBox(height: 16),
                  ],
                  TextField(
                    controller: _codeController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Reset code', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _newPasswordController,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'New password', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 20),
                  AppComponents.primaryButton(
                    text: _isLoading ? 'Resetting...' : 'Reset password',
                    onPressed: _isLoading ? null : _confirmReset,
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: TextButton(
                      onPressed: _isLoading ? null : _requestCode,
                      child: const Text('Resend code'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner(this.message);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red[200]!),
      ),
      child: Text(message, style: TextStyle(color: Colors.red[800], fontSize: 14)),
    );
  }
}
