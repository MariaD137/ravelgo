import 'package:flutter/material.dart';
import 'package:ravelgo_driver_app/services/api_client.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';
import 'package:ravelgo_driver_app/views/auth/vehicle_information_screen.dart';

class DriverInformationScreen extends StatefulWidget {
  final String email;
  const DriverInformationScreen({super.key, required this.email});

  @override
  State<DriverInformationScreen> createState() => _DriverInformationScreenState();
}

class _DriverInformationScreenState extends State<DriverInformationScreen> {
  final _licenseController = TextEditingController();
  final _experienceController = TextEditingController();
  String _selectedLanguage = 'English';
  bool _quietMode = false;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _licenseController.dispose();
    _experienceController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final license = _licenseController.text.trim();
    final experience = _experienceController.text.trim();

    if (license.isEmpty || experience.isEmpty) {
      setState(() => _errorMessage = 'Please fill in all required fields');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await ApiClient().post('/drivers/me', body: {
        'licenseNumber': license,
        'yearsOfExperience': int.tryParse(experience) ?? 0,
        'preferredLanguage': _selectedLanguage,
        'quietModePreferred': _quietMode,
      });

      if (!mounted) return;

      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => VehicleInformationScreen(email: widget.email)),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to save driver information. Please try again.';
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppComponents.header(context, "Driver information"),
              const SizedBox(height: 12),
              const Text(
                "This information is used for the Driver Matching Algorithm to pair you with the right riders",
                style: TextStyle(fontSize: 14, color: Colors.black54),
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
              TextField(
                controller: _licenseController,
                decoration: const InputDecoration(labelText: "Driver's License Number", border: OutlineInputBorder()),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _experienceController,
                decoration: const InputDecoration(labelText: "Years of driving experience", border: OutlineInputBorder()),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _selectedLanguage,
                decoration: const InputDecoration(labelText: "Preferred language", border: OutlineInputBorder()),
                items: const ["English", "French", "Yoruba", "Igbo", "Hausa"]
                    .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                    .toList(),
                onChanged: (value) {
                  if (value != null) setState(() => _selectedLanguage = value);
                },
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text("Prefer quiet rides (no small talk)"),
                value: _quietMode,
                onChanged: (value) => setState(() => _quietMode = value),
              ),
              const SizedBox(height: 24),
              AppComponents.uploadBox("Upload driver's license"),
              const SizedBox(height: 12),
              AppComponents.uploadBox("Upload background check consent"),
              const SizedBox(height: 28),
              AppComponents.primaryButton(
                text: _isLoading ? "Saving..." : "Continue",
                onPressed: _isLoading ? null : _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
