import 'package:flutter/material.dart';
import 'package:ravelgo_user_app/views/Login/ForgotPassword.dart';
import 'package:ravelgo_user_app/views/Signup/CreateAccount.dart';
import 'package:ravelgo_user_app/views/bottommenu/BottomNavigationView.dart';
import 'package:ravelgo_user_app/theme/app_theme.dart';

/// Rider sign-in.
///
/// AUTH BOUNDARY (MOCKED): there is no authentication backend, so credentials
/// cannot actually be verified. Input is validated locally (well-formed email,
/// non-empty password) and rejected with visible errors when invalid; valid
/// input proceeds to home. `_signIn` is the integration point for the future
/// auth service.
class Login extends StatefulWidget {
  const Login({super.key});

  @override
  State<Login> createState() => _LoginState();
}

class _LoginState extends State<Login> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  static final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _signIn() {
    if (!_formKey.currentState!.validate()) return;
    // Integration point: authenticate against the auth service here.
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => BottomNavigationView()),
      (Route<dynamic> route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('Sign in', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                const Text(
                  'Hi! Welcome back, you’ve been missed',
                  style: TextStyle(fontSize: 16, color: AppColors.textSecondary),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    border: OutlineInputBorder(),
                    hintText: 'example@mail.com',
                  ),
                  validator: (v) =>
                      (v == null || !_emailPattern.hasMatch(v.trim())) ? 'Enter a valid email address' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    border: const OutlineInputBorder(),
                    hintText: 'Enter password',
                    suffixIcon: IconButton(
                      icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                      onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                  validator: (v) => (v == null || v.length < 6) ? 'Password must be at least 6 characters' : null,
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    child: const Text('Forgot Password?', style: TextStyle(color: AppColors.primary)),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const ForgotPasswordScreen()),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _signIn,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                      textStyle: const TextStyle(fontSize: 18),
                    ),
                    child: const Text('Sign in'),
                  ),
                ),
                const SizedBox(height: 32),
                TextButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const CreateAccountScreen()),
                    );
                  },
                  child: const Text.rich(
                    TextSpan(
                      text: 'Don’t have an account? ',
                      style: TextStyle(color: AppColors.textPrimary),
                      children: [
                        TextSpan(text: 'Sign up', style: TextStyle(color: AppColors.primaryDark)),
                      ],
                    ),
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
