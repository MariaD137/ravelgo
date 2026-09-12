import 'package:flutter/material.dart';
import 'package:ravelgo_user_app/services/auth_service.dart';
import 'package:ravelgo_user_app/views/Signup/VerifyAccount.dart';
import 'package:ravelgo_user_app/theme/app_theme.dart';

/// Rider account creation. Collects rider details only - driver onboarding
/// (license, vehicle) lives exclusively in driver_app.
///
/// Validates input locally, then creates the account in the Cognito user
/// pool (AuthService.signUp) and hands off to VerifyAccountScreen for the
/// emailed confirmation code.
class CreateAccountScreen extends StatefulWidget {
  const CreateAccountScreen({super.key});

  @override
  State<CreateAccountScreen> createState() => _CreateAccountScreenState();
}

class _CreateAccountScreenState extends State<CreateAccountScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _agreedToTerms = false;
  bool _showTermsError = false;
  bool _obscurePassword = true;
  bool _loading = false;

  static final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _showTermsError = !_agreedToTerms);
    final valid = _formKey.currentState!.validate();
    if (!valid || !_agreedToTerms) return;

    final parts = _nameController.text.trim().split(RegExp(r'\s+'));
    final givenName = parts.first;
    final familyName = parts.length > 1 ? parts.sublist(1).join(' ') : parts.first;

    setState(() => _loading = true);
    try {
      await AuthService.signUp(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        givenName: givenName,
        familyName: familyName,
      );
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => VerifyAccountScreen(
            email: _emailController.text.trim(),
            password: _passwordController.text,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(AuthService.friendlyError(e))));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 6),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                const SizedBox(height: 6),
                const Text('Create your account', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                const Text('Ride with RavelGo in minutes', style: TextStyle(color: AppColors.textSecondary)),
                const SizedBox(height: 18),
                const Text('Full name'),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _nameController,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(hintText: 'Enter your full name'),
                  validator: (v) => (v == null || v.trim().length < 2) ? 'Enter your name' : null,
                ),
                const SizedBox(height: 12),
                const Text('Email'),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(hintText: 'Enter your email'),
                  validator: (v) =>
                      (v == null || !_emailPattern.hasMatch(v.trim())) ? 'Enter a valid email address' : null,
                ),
                const SizedBox(height: 12),
                const Text('Phone number'),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(hintText: 'Enter your phone number'),
                  validator: (v) {
                    final digits = (v ?? '').replaceAll(RegExp(r'\D'), '');
                    return digits.length < 7 ? 'Enter a valid phone number' : null;
                  },
                ),
                const SizedBox(height: 12),
                const Text('Password'),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    hintText: 'Create a password',
                    suffixIcon: IconButton(
                      icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                      onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                  validator: (v) {
                    final s = v ?? '';
                    if (s.length < 8) return 'At least 8 characters';
                    if (!RegExp(r'[A-Z]').hasMatch(s)) return 'Add an uppercase letter';
                    if (!RegExp(r'[a-z]').hasMatch(s)) return 'Add a lowercase letter';
                    if (!RegExp(r'[0-9]').hasMatch(s)) return 'Add a number';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                Row(children: [
                  Checkbox(
                    value: _agreedToTerms,
                    onChanged: (v) => setState(() {
                      _agreedToTerms = v ?? false;
                      if (_agreedToTerms) _showTermsError = false;
                    }),
                  ),
                  const Expanded(child: Text('I agree to the Terms & Conditions')),
                ]),
                if (_showTermsError)
                  const Padding(
                    padding: EdgeInsets.only(left: 12),
                    child: Text('You must accept the Terms & Conditions',
                        style: TextStyle(color: AppColors.error, fontSize: 12)),
                  ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _submit,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: _loading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('Create account', style: TextStyle(fontSize: 16)),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Center(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Already have an account? Sign in'),
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
