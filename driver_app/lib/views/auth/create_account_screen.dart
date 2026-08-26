import 'package:flutter/material.dart';
import 'package:ravelgo_driver_app/services/auth_service.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';
import 'package:ravelgo_driver_app/views/auth/add_photo_screen.dart';

/// Collects the driver's name/email/phone/password and creates the real
/// Cognito account via AuthService.signUp, then carries the profile fields
/// forward to AddPhotoScreen -> DriverInformationScreen, which is where the
/// Postgres-side profile is actually created via POST /drivers/me.
class CreateAccountScreen extends StatefulWidget {
  const CreateAccountScreen({super.key});

  @override
  State<CreateAccountScreen> createState() => _CreateAccountScreenState();
}

class _CreateAccountScreenState extends State<CreateAccountScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fullName = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _fullName.dispose();
    _email.dispose();
    _phone.dispose();
    _password.dispose();
    super.dispose();
  }

  String? _requiredValidator(String? value) => (value == null || value.trim().isEmpty) ? "Required" : null;

  String? _emailValidator(String? value) {
    if (value == null || value.trim().isEmpty) return "Required";
    if (!value.contains('@') || !value.contains('.')) return "Enter a valid email";
    return null;
  }

  Future<void> _continue() async {
    if (!_formKey.currentState!.validate()) return;

    final fullName = _fullName.text.trim();
    final email = _email.text.trim();
    final phone = _phone.text.trim();
    final parts = fullName.split(RegExp(r'\s+'));
    final firstName = parts.first;
    final lastName = parts.length > 1 ? parts.sublist(1).join(' ') : '';

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final result = await AuthService().signUp(email, _password.text, fullName, phone);

      if (!mounted) return;

      if (result['success'] == true) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => AddPhotoScreen(
              firstName: firstName,
              lastName: lastName,
              email: email,
              phoneNumber: phone,
            ),
          ),
        );
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = result['error'] as String?;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Sign up failed. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppComponents.header(context, "Create driver account"),
                const SizedBox(height: 12),
                const Text(
                  "Let's get you set up to start earning with RavelGo",
                  style: TextStyle(fontSize: 15, color: Colors.black54),
                ),
                const SizedBox(height: 24),
                if (_errorMessage != null) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red[200]!),
                    ),
                    child: Text(
                      _errorMessage!,
                      style: TextStyle(color: Colors.red[800], fontSize: 14),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                TextFormField(
                  controller: _fullName,
                  decoration: const InputDecoration(labelText: 'Full name *', border: OutlineInputBorder()),
                  validator: _requiredValidator,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email *', border: OutlineInputBorder()),
                  validator: _emailValidator,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Phone number', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _password,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Password *', border: OutlineInputBorder()),
                  validator: (value) => (value == null || value.length < 8) ? "At least 8 characters" : null,
                ),
                const SizedBox(height: 28),
                AppComponents.primaryButton(
                  text: _isLoading ? "Creating account..." : "Continue",
                  onPressed: _isLoading ? null : _continue,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
