import 'package:flutter/material.dart';
import 'package:ravelgo_user/services/auth_service.dart';
import 'package:ravelgo_user/views/Signup/verify_account.dart';

class CreateAccountScreen extends StatefulWidget {
  const CreateAccountScreen({super.key});

  @override
  State<CreateAccountScreen> createState() => _CreateAccountScreenState();
}

class _CreateAccountScreenState extends State<CreateAccountScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _phoneController = TextEditingController();
  final _nameController = TextEditingController();
  bool _agreedToTerms = false;
  bool _isLoading = false;
  String? _errorMessage;

  final _fieldDecoration = InputDecoration(
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(6.0)),
    contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 18),
  );

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _phoneController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _signUp() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final phone = _phoneController.text.trim();
    final name = _nameController.text.trim();

    if (email.isEmpty || password.isEmpty || phone.isEmpty) {
      setState(() => _errorMessage = 'Please fill in all required fields');
      return;
    }
    if (!_agreedToTerms) {
      setState(() => _errorMessage = 'Please agree to the Terms & Conditions');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final result = await AuthService().signUp(email, password, name, phone);

    if (!mounted) return;

    if (result['success'] == true) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => VerifyAccountScreen(email: email)),
      );
    } else {
      setState(() {
        _isLoading = false;
        _errorMessage = result['error'] as String?;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(height: 6),
              IconButton(icon: Icon(Icons.close), onPressed: () => Navigator.pop(context)),
              SizedBox(height: 6),
              Text('Create an account', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Text('Fill your information below to get started', style: TextStyle(color: Colors.grey[600])),
              SizedBox(height: 18),
              if (_errorMessage != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red[200]!),
                  ),
                  child: Text(_errorMessage!, style: TextStyle(color: Colors.red[800], fontSize: 14)),
                ),
                SizedBox(height: 12),
              ],
              Text('Full Name'),
              SizedBox(height: 6),
              TextField(controller: _nameController, decoration: _fieldDecoration.copyWith(hintText: 'Enter your name')),
              SizedBox(height: 12),
              Text('Email'),
              SizedBox(height: 6),
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: _fieldDecoration.copyWith(hintText: 'Enter Email'),
              ),
              SizedBox(height: 12),
              Text('Password'),
              SizedBox(height: 6),
              TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: _fieldDecoration.copyWith(hintText: 'Min 8 chars, uppercase, lowercase, number'),
              ),
              SizedBox(height: 12),
              Text('Phone Number'),
              SizedBox(height: 6),
              TextField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: _fieldDecoration.copyWith(hintText: '+1234567890'),
              ),
              SizedBox(height: 12),
              Row(children: [
                Checkbox(
                  value: _agreedToTerms,
                  onChanged: (v) => setState(() => _agreedToTerms = v ?? false),
                ),
                Expanded(child: Text('Agree with Terms & Conditions'))
              ]),
              SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _signUp,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.yellow[700],
                    foregroundColor: Colors.black,
                    disabledBackgroundColor: Colors.yellow[100],
                  ),
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: _isLoading
                        ? SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : Text('Create account', style: TextStyle(fontSize: 16)),
                  ),
                ),
              ),
              SizedBox(height: 18),
              Center(
                child: GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Text('Already have an account? Sign in', style: TextStyle(color: Colors.blue)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
