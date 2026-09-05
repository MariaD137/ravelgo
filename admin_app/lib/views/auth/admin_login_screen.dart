import 'package:flutter/material.dart';
import 'package:ravelgo_admin/services/auth_service.dart';
import 'package:ravelgo_admin/theme/app_theme.dart';
import 'package:ravelgo_admin/views/auth/forgot_password_screen.dart';
import 'package:ravelgo_admin/views/shell/admin_shell.dart';

/// Admin sign-in, backed by the real RavelGo Cognito user pool.
///
/// Every admin API call is independently enforced server-side
/// (requireRole("Admin")) — that is the authoritative check and this screen
/// cannot weaken it. This client-side group check exists purely for UX: it
/// rejects a non-admin with a clear message before they ever see the
/// dashboard, instead of a confusing wall of 403s on every screen.
class AdminLoginScreen extends StatefulWidget {
  /// Shown once on load — e.g. after a restored session turned out not to
  /// belong to an Admin.
  final String? initialError;
  const AdminLoginScreen({super.key, this.initialError});

  @override
  State<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _loading = false;

  static final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  @override
  void initState() {
    super.initState();
    if (widget.initialError != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(widget.initialError!)));
      });
    }
  }

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
      if (!AuthService.isAdmin) {
        await AuthService.signOut();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('You are not authorized to access the RavelGo Admin Console.'),
        ));
        return;
      }
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const AdminShell()),
        (route) => false,
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
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 40),
                  const Text("RavelGo Admin", style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text("Sign in to manage drivers, riders, trips and operations",
                      style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
                  const SizedBox(height: 32),
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration:
                        const InputDecoration(labelText: "Work email", border: OutlineInputBorder()),
                    validator: (v) => (v == null || !_emailPattern.hasMatch(v.trim()))
                        ? 'Enter a valid email address'
                        : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    decoration: InputDecoration(
                      labelText: "Password",
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                        onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                      ),
                    ),
                    validator: (v) =>
                        (v == null || v.length < 8) ? 'Password must be at least 8 characters' : null,
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                        onPressed: () {
                          Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (context) => const ForgotPasswordScreen()));
                        },
                        child: Text("Forgot Password?",
                            style: TextStyle(color: AppColors.primaryDark))),
                  ),
                  const SizedBox(height: 20),
                  AppComponents.primaryButton(
                      text: _loading ? "Signing in…" : "Sign in",
                      onPressed: _loading ? null : _signIn),
                  const SizedBox(height: 16),
                  const Center(
                    child: Text("Access is restricted to authorized RavelGo staff.",
                        style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
