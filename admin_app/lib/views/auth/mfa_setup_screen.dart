import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:ravelgo_admin/services/admin_api.dart';
import 'package:ravelgo_admin/services/auth_service.dart';
import 'package:ravelgo_admin/theme/app_theme.dart';
import 'package:ravelgo_admin/views/shell/admin_shell.dart';

/// Mandatory TOTP MFA enrollment. Shown right after a fully-authenticated
/// sign-in (no outstanding Cognito challenge) whenever GET /admin-users/me
/// reports mfaEnabled: false — there is no way to skip or dismiss this
/// screen, matching the product requirement that an admin isn't considered
/// fully active until MFA setup is complete. See auth_service.dart's
/// beginMfaEnrollment/completeMfaEnrollment doc comments for why this is an
/// app-layer gate rather than a Cognito pool-level requirement (the pool is
/// shared with Riders/Drivers, who must NOT be forced into MFA).
class MfaSetupScreen extends StatefulWidget {
  const MfaSetupScreen({super.key});

  @override
  State<MfaSetupScreen> createState() => _MfaSetupScreenState();
}

class _MfaSetupScreenState extends State<MfaSetupScreen> {
  final _codeController = TextEditingController();
  bool _loading = true;
  bool _verifying = false;
  String? _secret;
  String? _otpauthUri;
  String? _error;

  @override
  void initState() {
    super.initState();
    _startEnrollment();
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _startEnrollment() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await AuthService.beginMfaEnrollment();
      if (!mounted) return;
      setState(() {
        _secret = result.secret;
        _otpauthUri = result.otpauthUri;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = AuthService.friendlyError(e);
        _loading = false;
      });
    }
  }

  Future<void> _verify() async {
    final code = _codeController.text.trim();
    if (code.length < 6) {
      setState(
        () => _error = 'Enter the 6-digit code from your authenticator app.',
      );
      return;
    }
    setState(() {
      _error = null;
      _verifying = true;
    });
    try {
      final ok = await AuthService.completeMfaEnrollment(code: code);
      if (!ok) {
        if (!mounted) return;
        setState(() {
          _error =
              'That code is incorrect. Check your authenticator app and try again.';
          _verifying = false;
        });
        return;
      }
      // Best-effort audit trail entry — MFA is already enabled in Cognito at
      // this point regardless of whether this call succeeds.
      try {
        await AdminApi.recordMfaEnrolled();
      } catch (_) {}
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Two-factor authentication enabled.')),
      );
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const AdminShell()),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = AuthService.friendlyError(e);
        _verifying = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Mandatory step — no back button, no way to reach the app without it.
      canPop: false,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 16,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Set up two-factor authentication',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'RavelGo Admin requires an authenticator app for every admin account. '
                        'Scan this QR code with an app like Google Authenticator or Authy, then enter the 6-digit code it shows.',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 24),
                      if (_otpauthUri != null)
                        Center(
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: QrImageView(
                              data: _otpauthUri!,
                              size: 200,
                              backgroundColor: Colors.white,
                            ),
                          ),
                        ),
                      const SizedBox(height: 16),
                      if (_secret != null) ...[
                        const Text(
                          "Can't scan it? Enter this key manually:",
                          style: TextStyle(
                            fontSize: 12.5,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        InkWell(
                          onTap: () {
                            Clipboard.setData(ClipboardData(text: _secret!));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Key copied')),
                            );
                          },
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceElevated,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    _secret!,
                                    style: const TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                                const Icon(
                                  Icons.copy,
                                  size: 16,
                                  color: AppColors.textSecondary,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      TextField(
                        controller: _codeController,
                        keyboardType: TextInputType.number,
                        maxLength: 6,
                        decoration: const InputDecoration(
                          labelText: '6-digit code',
                          counterText: '',
                        ),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          _error!,
                          style: const TextStyle(color: AppColors.danger),
                        ),
                      ],
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _verifying ? null : _verify,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            child: _verifying
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text('Verify and enable'),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Center(
                        child: TextButton(
                          onPressed: _loading ? null : _startEnrollment,
                          child: const Text('Get a new code'),
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}
