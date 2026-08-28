import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ravelgo_user_app/views/Signup/AddPhoto.dart';
import 'package:ravelgo_user_app/theme/app_theme.dart';

/// Rider account verification (OTP entry).
///
/// AUTH BOUNDARY: no verification backend is connected yet, so no code is
/// actually sent. Input is validated locally (6 digits) and "Resend code" is
/// rate-limited UI only - both hooks are the integration points for the
/// future auth/OTP service. This screen never claims a code was delivered.
class VerifyAccountScreen extends StatefulWidget {
  final String? email;
  const VerifyAccountScreen({super.key, this.email});

  @override
  State<VerifyAccountScreen> createState() => _VerifyAccountScreenState();
}

class _VerifyAccountScreenState extends State<VerifyAccountScreen> {
  final _otpController = TextEditingController();
  String? _error;
  int _resendCooldown = 0;
  Timer? _cooldownTimer;

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _otpController.dispose();
    super.dispose();
  }

  void _verify() {
    final code = _otpController.text.trim();
    if (code.length != 6 || int.tryParse(code) == null) {
      setState(() => _error = 'Enter the 6-digit code');
      return;
    }
    setState(() => _error = null);
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const AddPhotoScreen()),
    );
  }

  void _resend() {
    if (_resendCooldown > 0) return;
    // Integration point: request a new OTP from the auth service here.
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Verification service not connected yet - code delivery requires the auth backend.'),
    ));
    setState(() => _resendCooldown = 30);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() {
        _resendCooldown -= 1;
        if (_resendCooldown <= 0) t.cancel();
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final target = widget.email == null ? 'your email address' : widget.email!;
    return Scaffold(
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Verify your account', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text('Enter the 6-digit code sent to $target.',
                style: const TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 18),
            const Text('Verification code'),
            const SizedBox(height: 6),
            TextField(
              controller: _otpController,
              keyboardType: TextInputType.number,
              maxLength: 6,
              decoration: InputDecoration(hintText: 'Enter code', counterText: '', errorText: _error),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _resendCooldown > 0 ? null : _resend,
                child: Text(_resendCooldown > 0 ? 'Resend code (${_resendCooldown}s)' : 'Resend code'),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _verify,
                child: const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Text('Verify')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
