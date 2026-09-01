import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ravelgo_driver_app/services/auth_service.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';
import 'package:ravelgo_driver_app/views/shell/driver_shell.dart';

/// Driver account verification. Confirms the emailed Cognito code, then signs
/// the driver in and enters the app.
class VerifyAccountScreen extends StatefulWidget {
  final String? email;
  final String? password;
  const VerifyAccountScreen({super.key, this.email, this.password});

  @override
  State<VerifyAccountScreen> createState() => _VerifyAccountScreenState();
}

class _VerifyAccountScreenState extends State<VerifyAccountScreen> {
  final _codeController = TextEditingController();
  String? _error;
  bool _loading = false;
  int _resendCooldown = 0;
  Timer? _cooldownTimer;

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final code = _codeController.text.trim();
    if (code.length != 6 || int.tryParse(code) == null) {
      setState(() => _error = 'Enter the 6-digit code');
      return;
    }
    setState(() {
      _error = null;
      _loading = true;
    });
    try {
      final email = widget.email ?? '';
      await AuthService.confirm(email: email, code: code);
      if ((widget.password ?? '').isNotEmpty) {
        await AuthService.signIn(email: email, password: widget.password!);
      }
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const DriverShell()),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = AuthService.friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resend() async {
    if (_resendCooldown > 0) return;
    try {
      await AuthService.resendCode(email: widget.email ?? '');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('A new code has been sent to your email.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(AuthService.friendlyError(e))));
    }
    setState(() => _resendCooldown = 30);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return timer.cancel();
      setState(() {
        _resendCooldown -= 1;
        if (_resendCooldown <= 0) timer.cancel();
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final target = widget.email ?? 'your email address';
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppComponents.header(context, "Verify your account"),
              const SizedBox(height: 24),
              Text("Enter the 6-digit code sent to $target",
                  style: const TextStyle(fontSize: 14, color: AppColors.textSecondary)),
              const SizedBox(height: 20),
              TextField(
                controller: _codeController,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: InputDecoration(
                  hintText: 'Enter code',
                  counterText: '',
                  border: const OutlineInputBorder(),
                  errorText: _error,
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _resendCooldown > 0 ? null : _resend,
                  child: Text(_resendCooldown > 0 ? "Resend code (${_resendCooldown}s)" : "Resend code"),
                ),
              ),
              const Spacer(),
              const Text(
                "Your application will be reviewed within 24-48 hours. You can go online as soon as your documents are approved.",
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 12),
              AppComponents.primaryButton(
                text: _loading ? "Verifying…" : "Verify & finish",
                onPressed: _loading ? null : _verify,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
