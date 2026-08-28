import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';
import 'package:ravelgo_driver_app/views/shell/driver_shell.dart';

/// AUTH BOUNDARY: no verification backend is connected, so no code is sent.
/// "Resend code" is rate-limited UI that states the boundary honestly.
class VerifyAccountScreen extends StatefulWidget {
  const VerifyAccountScreen({super.key});

  @override
  State<VerifyAccountScreen> createState() => _VerifyAccountScreenState();
}

class _VerifyAccountScreenState extends State<VerifyAccountScreen> {
  int _resendCooldown = 0;
  Timer? _cooldownTimer;

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    super.dispose();
  }

  void _resend() {
    if (_resendCooldown > 0) return;
    // Integration point: request a new OTP from the auth service here.
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Verification service not connected yet - code delivery requires the auth backend.'),
    ));
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
              const Text("Enter the 6-digit code sent to your phone number", style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(
                  6,
                  (i) => SizedBox(
                    width: 44,
                    child: TextField(
                      textAlign: TextAlign.center,
                      keyboardType: TextInputType.number,
                      maxLength: 1,
                      decoration: const InputDecoration(counterText: "", border: OutlineInputBorder()),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Center(
                child: TextButton(
                  onPressed: _resendCooldown > 0 ? null : _resend,
                  child: Text(_resendCooldown > 0
                      ? "Resend code (${_resendCooldown}s)"
                      : "Resend code"),
                ),
              ),
              const Spacer(),
              const Text(
                "Your application will be reviewed within 24-48 hours. You can go online as soon as your documents are approved.",
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 12),
              AppComponents.primaryButton(
                text: "Verify & finish",
                onPressed: () {
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (context) => const DriverShell()),
                    (route) => false,
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
