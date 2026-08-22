import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';
import 'package:ravelgo_rider_app/services/api/auth_provider.dart';
import 'package:ravelgo_rider_app/views/Signup/CreateAccount.dart';
import 'package:ravelgo_rider_app/views/bottommenu/BottomNavigationView.dart';

class Login extends StatefulWidget {
  const Login({super.key, required this.authProvider});

  final AuthProvider authProvider;

  @override
  State<Login> createState() => _LoginState();
}

class _LoginState extends State<Login> {
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
      MaterialPageRoute(builder: (context) => BottomNavigationView()),
      (Route<dynamic> route) => false,
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
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Sign in',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'Hi! Welcome back, you’ve been missed',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey[600],
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 32),
              TextField(
                controller: _emailController,
                enabled: !submitting,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: 'Email',
                  border: OutlineInputBorder(),
                  hintText: 'example@mail.com',
                ),
              ),
              SizedBox(height: 16),
              TextField(
                controller: _passwordController,
                enabled: !submitting,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'Password',
                  border: OutlineInputBorder(),
                  hintText: 'Enter password',
                  suffixIcon: IconButton(
                    icon: Icon(Icons.visibility_off),
                    onPressed: () {},
                  ),
                ),
              ),
              if (_authStatus == AuthStatus.authenticationFailed) ...[
                const SizedBox(height: 12),
                Text(
                  _authErrorMessage ?? 'Sign in failed.',
                  style: const TextStyle(color: Colors.red, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              ],
              SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  child: Text(
                    'Forgot Password?',
                    style: TextStyle(color: Colors.yellow[700]),
                  ),
                  onPressed: () {},
                ),
              ),
              SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: submitting ? null : _handleSignIn,
                  child: Text(submitting ? 'Signing in…' : 'Sign in'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.yellow[700],
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    textStyle: TextStyle(fontSize: 18),
                  ),
                ),
              ),
              SizedBox(height: 32),
              TextButton(
                onPressed: () {
                  Navigator.push(context,
                    MaterialPageRoute(builder: (context) => CreateAccountScreen()),
                  );
                },
                child: Text.rich(
                  TextSpan(
                    text: "Don’t have an account? ",
                    style: TextStyle(color: Colors.black),
                    children: [
                      TextSpan(
                        text: "Sign up",
                        style: TextStyle(color: Color(0xFF665600)),
                      ),
                    ],
                  ),
                ),
              ),
              if (!kReleaseMode) _buildDevOnlySignIn(),
            ],
          ),
        ),
      ),
    );
  }
}
