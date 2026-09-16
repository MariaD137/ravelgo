import 'dart:async';
import 'package:amazon_cognito_identity_dart_2/cognito.dart';
import 'package:flutter/material.dart';
import 'package:ravelgo_driver_app/services/auth_service.dart';
import 'package:ravelgo_driver_app/services/push_notification_service.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';
import 'package:ravelgo_driver_app/views/auth/create_account_screen.dart';
import 'package:ravelgo_driver_app/views/auth/forgot_password_screen.dart';
import 'package:ravelgo_driver_app/views/auth/set_new_password_screen.dart';
import 'package:ravelgo_driver_app/views/shell/driver_shell.dart';

/// Driver sign-in, wired to the RavelGo Cognito user pool via [AuthService].
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _loading = false;

  static final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      await AuthService.signIn(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      unawaited(PushNotificationService.configureAndRegister());
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const DriverShell()),
        (route) => false,
      );
    } on CognitoUserNewPasswordRequiredException {
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => SetNewPasswordScreen(email: _emailController.text.trim())),
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
      backgroundColor: AppColors.background,
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
                Image.asset('assets/ravel_go_driver_badge.png', height: 48),
                const SizedBox(height: 24),
                const Text('Driver Sign in', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                const Text(
                  'Welcome back! Sign in to go online and start earning',
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
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const ForgotPasswordScreen()),
                      );
                    },
                    child: const Text('Forgot Password?', style: TextStyle(color: AppColors.primaryDark)),
                  ),
                ),
                const SizedBox(height: 24),
                AppComponents.primaryButton(
                    text: _loading ? 'Signing in…' : 'Sign in',
                    onPressed: _loading ? null : _signIn),
                const SizedBox(height: 24),
                TextButton(
                  onPressed: () {
                    Navigator.push(
                        context, MaterialPageRoute(builder: (context) => const CreateAccountScreen()));
                  },
                  child: const Text.rich(
                    TextSpan(
                      text: "New driver? ",
                      style: TextStyle(color: AppColors.textPrimary),
                      children: [
                        TextSpan(text: "Create an account", style: TextStyle(color: AppColors.primaryDark)),
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
