import 'package:flutter/material.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';

/// Password-reset entry for drivers.
/// AUTH BOUNDARY: no authentication backend is connected, so no reset email
/// can be sent. The screen validates the address and states that clearly -
/// it never claims an email was sent. `_requestReset` is the integration
/// point for the auth service.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailController = TextEditingController();
  String? _error;
  bool _submitted = false;

  static final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  void _requestReset() {
    final email = _emailController.text.trim();
    if (!_emailPattern.hasMatch(email)) {
      setState(() => _error = 'Enter a valid email address');
      return;
    }
    // Integration point: call the auth service's password-reset endpoint.
    setState(() {
      _error = null;
      _submitted = true;
    });
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
            const Text('Reset your password', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text(
              "Enter the email you drive with and we'll help you get back in.",
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(labelText: 'Email', hintText: 'example@mail.com', errorText: _error),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _submitted ? null : _requestReset,
                child: const Padding(padding: EdgeInsets.symmetric(vertical: 14), child: Text('Continue')),
              ),
            ),
            if (_submitted) ...[
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: const Text(
                  'Password reset is not available yet: this build is not connected to the '
                  'authentication service, so no reset email can be sent. Please contact '
                  'driver support to regain access.',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
