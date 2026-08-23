import 'package:flutter/material.dart';
import 'package:ravelgo_driver_app/models/driver_onboarding_draft.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';
import 'package:ravelgo_driver_app/views/auth/add_photo_screen.dart';

class CreateAccountScreen extends StatefulWidget {
  const CreateAccountScreen({super.key});

  @override
  State<CreateAccountScreen> createState() => _CreateAccountScreenState();
}

class _CreateAccountScreenState extends State<CreateAccountScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _email.dispose();
    _phone.dispose();
    super.dispose();
  }

  void _continue() {
    if (!_formKey.currentState!.validate()) return;
    final draft = DriverOnboardingDraft()
      ..firstName = _firstName.text.trim()
      ..lastName = _lastName.text.trim()
      ..email = _email.text.trim()
      ..phoneNumber = _phone.text.trim();
    Navigator.push(context, MaterialPageRoute(builder: (context) => AddPhotoScreen(draft: draft)));
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
                  controller: _firstName,
                  decoration: const InputDecoration(labelText: 'First name', border: OutlineInputBorder()),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _lastName,
                  decoration: const InputDecoration(labelText: 'Last name', border: OutlineInputBorder()),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder()),
                  validator: (v) {
                    final value = v?.trim() ?? '';
                    if (value.isEmpty) return 'Required';
                    if (!value.contains('@') || !value.contains('.')) return 'Enter a valid email';
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Phone number', border: OutlineInputBorder()),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
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
