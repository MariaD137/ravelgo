import 'package:flutter/material.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';
import 'package:ravelgo_driver_app/views/auth/add_photo_screen.dart';

/// Collects the driver's name/email/phone (and a password, for the Cognito
/// sign-up this app doesn't implement yet — see AuthTokenProvider's doc
/// comment) and carries them forward to AddPhotoScreen ->
/// DriverInformationScreen, which is where the profile is actually
/// submitted via POST /drivers/me. This screen itself makes no API call —
/// there's no account to create one under until Cognito sign-up exists.
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

  void _continue() {
    if (!_formKey.currentState!.validate()) return;

    final parts = _fullName.text.trim().split(RegExp(r'\s+'));
    final firstName = parts.first;
    final lastName = parts.length > 1 ? parts.sublist(1).join(' ') : '';

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddPhotoScreen(
          firstName: firstName,
          lastName: lastName,
          email: _email.text.trim(),
          phoneNumber: _phone.text.trim(),
        ),
      ),
    );
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
                AppComponents.primaryButton(text: "Continue", onPressed: _continue),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
