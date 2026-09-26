import 'package:flutter/material.dart';
import 'package:ravelgo_driver_app/services/auth_service.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';

/// The sign-in-time two-factor step for an account with TOTP MFA enrolled
/// (AuthService.signIn() threw CognitoUserTotpRequiredException). Pops with
/// `true` once the code is accepted and the session is applied, so the login
/// screen can carry on with its normal post-sign-in steps.
class MfaCodeScreen extends StatefulWidget {
  const MfaCodeScreen({super.key});

  @override
  State<MfaCodeScreen> createState() => _MfaCodeScreenState();
}

class _MfaCodeScreenState extends State<MfaCodeScreen> {
  final _codeController = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final code = _codeController.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      setState(() => _error = 'Enter the 6-digit code from your authenticator app.');
      return;
    }
    setState(() {
      _error = null;
      _loading = true;
    });
    try {
      await AuthService.submitMfaCode(code: code);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString();
      // Cognito's MFA session lasts ~3 minutes; once it lapses the challenge
      // answer is rejected with NotAuthorized, which friendlyError() would
      // otherwise misreport as a wrong password.
      setState(() => _error = msg.contains('NotAuthorized') || msg.contains('session expired')
          ? 'This sign-in timed out. Go back and sign in again.'
          : AuthService.friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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
              AppComponents.header(context, "Two-factor verification"),
              const SizedBox(height: 24),
              const Text("Enter the 6-digit code from your authenticator app.",
                  style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
              const SizedBox(height: 20),
              TextField(
                controller: _codeController,
                keyboardType: TextInputType.number,
                maxLength: 6,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Enter code',
                  counterText: '',
                  border: const OutlineInputBorder(),
                  errorText: _error,
                ),
                onSubmitted: (_) => _loading ? null : _verify(),
              ),
              const Spacer(),
              AppComponents.primaryButton(
                text: _loading ? "Verifying…" : "Verify",
                onPressed: _loading ? null : _verify,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
