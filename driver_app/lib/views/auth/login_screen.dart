import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';
import 'package:ravelgo_driver_app/services/api/auth_provider.dart';
import 'package:ravelgo_driver_app/services/driver_session.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';
import 'package:ravelgo_driver_app/views/auth/create_account_screen.dart';
import 'package:ravelgo_driver_app/views/shell/driver_shell.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _devTokenController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _devTokenController.dispose();
    super.dispose();
  }

  void _navigateToDriverShell() {
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => const DriverShell()),
      (route) => false,
    );
  }

  Future<void> _handleSignIn() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter your email and password.')),
      );
      return;
    }

    final succeeded = await DriverSession.instance.signIn(username: email, password: password);
    if (succeeded) {
      _navigateToDriverShell();
    }
    // On failure, DriverSession.instance.authStatus/authErrorMessage
    // already reflect it — the AnimatedBuilder below re-renders to show it,
    // no separate local error state needed.
  }

  /// DEVELOPMENT ONLY, compiled out entirely in release builds (the whole
  /// section this builds is wrapped in `if (!kReleaseMode)` below — not
  /// just hidden, absent from the release build's widget tree). Lets a
  /// developer paste a token obtained some other way (a local backend's own
  /// test-token minting, an integration-test harness) to exercise the
  /// backend-wired screens before Cognito exists. It never fabricates a
  /// token itself — [DevOnlyAuthProvider.setToken] just stores whatever
  /// was typed in.
  Widget _buildDevOnlySignIn() {
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Divider(),
          const SizedBox(height: 8),
          const Text(
            'DEVELOPMENT ONLY — paste a token from a local test backend. '
            'Never available in a release build.',
            style: TextStyle(fontSize: 12, color: Colors.red),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _devTokenController,
            decoration: const InputDecoration(
              labelText: 'Dev access token',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () {
              final token = _devTokenController.text.trim();
              if (token.isEmpty) return;
              DevOnlyAuthProvider.instance.setToken(token);
              _navigateToDriverShell();
            },
            child: const Text('Dev sign in (debug only)'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: AnimatedBuilder(
            animation: DriverSession.instance,
            builder: (context, _) {
              final authStatus = DriverSession.instance.authStatus;
              final submitting = authStatus == AuthStatus.authenticating;
              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Image.asset('assets/ravel_go_driver_badge.png', height: 48),
                  const SizedBox(height: 24),
                  const Text('Driver Sign in', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text(
                    'Welcome back! Sign in to go online and start earning',
                    style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  TextField(
                    controller: _emailController,
                    enabled: !submitting,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      border: OutlineInputBorder(),
                      hintText: 'example@mail.com',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _passwordController,
                    enabled: !submitting,
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
                  ),
                  if (authStatus == AuthStatus.authenticationFailed) ...[
                    const SizedBox(height: 12),
                    Text(
                      DriverSession.instance.authErrorMessage ?? 'Sign in failed.',
                      style: const TextStyle(color: Colors.red, fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () {},
                      child: Text('Forgot Password?', style: TextStyle(color: Colors.yellow[700])),
                    ),
                  ),
                  const SizedBox(height: 24),
                  AppComponents.primaryButton(
                    text: submitting ? 'Signing in…' : 'Sign in',
                    onPressed: submitting ? null : _handleSignIn,
                  ),
                  const SizedBox(height: 24),
                  TextButton(
                    onPressed: () {
                      Navigator.push(context, MaterialPageRoute(builder: (context) => const CreateAccountScreen()));
                    },
                    child: Text.rich(
                      TextSpan(
                        text: "New driver? ",
                        style: const TextStyle(color: Colors.black),
                        children: [
                          TextSpan(text: "Create an account", style: TextStyle(color: AppColors.primaryDark)),
                        ],
                      ),
                    ),
                  ),
                  if (!kReleaseMode) _buildDevOnlySignIn(),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
