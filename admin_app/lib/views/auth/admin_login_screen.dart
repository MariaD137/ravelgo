import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';
import 'package:ravelgo_admin/services/api/auth_provider.dart';
import 'package:ravelgo_admin/theme/app_theme.dart';
import 'package:ravelgo_admin/views/shell/admin_shell.dart';

class AdminLoginScreen extends StatefulWidget {
  const AdminLoginScreen({super.key, required this.authProvider});

  final AuthProvider authProvider;

  @override
  State<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _devTokenController = TextEditingController();
  AuthStatus _authStatus = AuthStatus.unauthenticated;
  String? _authErrorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _devTokenController.dispose();
    super.dispose();
  }

  void _navigateIn() {
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => AdminShell(authProvider: widget.authProvider)),
      (route) => false,
    );
  }

  Future<void> _handleSignIn() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter your work email and password.')),
      );
      return;
    }

    setState(() {
      _authStatus = AuthStatus.authenticating;
      _authErrorMessage = null;
    });
    try {
      await widget.authProvider.login(username: email, password: password);
      if (!mounted) return;
      setState(() => _authStatus = AuthStatus.authenticated);
      _navigateIn();
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _authStatus = AuthStatus.authenticationFailed;
        _authErrorMessage = err.toString();
      });
    }
  }

  /// DEVELOPMENT ONLY, compiled out entirely in release builds. Lets a
  /// developer paste a token obtained some other way (a local backend's own
  /// test-token minting, an integration-test harness) to exercise the
  /// backend-wired screens before Cognito exists. Never fabricates a token
  /// itself — [DevOnlyAuthProvider.setToken] just stores whatever was typed.
  Widget _buildDevOnlySignIn() {
    final provider = widget.authProvider;
    if (provider is! DevOnlyAuthProvider) return const SizedBox.shrink();
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
            decoration: const InputDecoration(labelText: 'Dev access token', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () {
              final token = _devTokenController.text.trim();
              if (token.isEmpty) return;
              provider.setToken(token);
              _navigateIn();
            },
            child: const Text('Dev sign in (debug only)'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final submitting = _authStatus == AuthStatus.authenticating;
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 40),
                const Text("RavelGo Admin", style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                const Text("Sign in to manage drivers, riders, trips and operations", style: TextStyle(fontSize: 14, color: Colors.black54)),
                const SizedBox(height: 32),
                TextField(
                  controller: _emailController,
                  enabled: !submitting,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: "Work email", border: OutlineInputBorder()),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _passwordController,
                  enabled: !submitting,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: "Password", border: OutlineInputBorder(), suffixIcon: Icon(Icons.visibility_off)),
                ),
                if (_authStatus == AuthStatus.authenticationFailed) ...[
                  const SizedBox(height: 12),
                  Text(
                    _authErrorMessage ?? 'Sign in failed.',
                    style: const TextStyle(color: Colors.red, fontSize: 13),
                  ),
                ],
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(onPressed: () {}, child: Text("Forgot Password?", style: TextStyle(color: Colors.yellow[700]))),
                ),
                const SizedBox(height: 20),
                AppComponents.primaryButton(
                  text: submitting ? "Signing in…" : "Sign in",
                  onPressed: submitting ? null : _handleSignIn,
                ),
                const SizedBox(height: 16),
                const Center(
                  child: Text("Access is restricted to authorized RavelGo staff.", style: TextStyle(fontSize: 12, color: Colors.black45)),
                ),
                if (!kReleaseMode) _buildDevOnlySignIn(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
