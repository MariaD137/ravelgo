import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:ravelgo_driver_app/services/auth_session.dart';
import 'package:ravelgo_driver_app/services/driver_api.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';
import 'package:ravelgo_driver_app/views/auth/verify_account_screen.dart';
import 'package:ravelgo_driver_app/views/vehicles/add_vehicle_screen.dart';

class DriverInformationScreen extends StatefulWidget {
  final String firstName;
  final String lastName;
  final String email;
  final String phoneNumber;

  const DriverInformationScreen({
    super.key,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.phoneNumber,
  });

  @override
  State<DriverInformationScreen> createState() => _DriverInformationScreenState();
}

class _DriverInformationScreenState extends State<DriverInformationScreen> {
  late final DriverApi _api =
      DriverApi(baseUrl: dotenv.env['API_BASE_URL'] ?? '', authTokenProvider: const CognitoAuthTokenProvider());

  static const _languages = ["English", "French", "Yoruba", "Igbo", "Hausa"];
  String _preferredLanguage = _languages.first;
  bool _quietModePreferred = false;

  bool _submitting = false;
  String? _submitError;

  Future<void> _continue() async {
    setState(() {
      _submitting = true;
      _submitError = null;
    });
    try {
      // The actual profile-creation call (POST /drivers/me) — authenticated
      // with the real Cognito access token from sign-up (see
      // CognitoAuthTokenProvider / auth_service.dart).
      await _api.createDriverProfile(
        firstName: widget.firstName,
        lastName: widget.lastName,
        email: widget.email,
        phoneNumber: widget.phoneNumber,
        preferredLanguage: _preferredLanguage,
        quietModePreferred: _quietModePreferred,
      );
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => AddVehicleScreen(
            api: _api,
            onSaved: () => Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const VerifyAccountScreen()),
            ),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitError = e is DriverApiException ? e.message : "Unable to save your profile";
        _submitting = false;
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
              DropdownButtonFormField<String>(
                initialValue: _preferredLanguage,
                decoration: const InputDecoration(labelText: "Preferred language", border: OutlineInputBorder()),
                items: _languages.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                onChanged: (value) {
                  if (value != null) setState(() => _preferredLanguage = value);
                },
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text("Prefer quiet rides (no small talk)"),
                value: _quietModePreferred,
                onChanged: (value) => setState(() => _quietModePreferred = value),
              ),
              if (_submitError != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: AppColors.danger.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                  child: Text(_submitError!, style: const TextStyle(color: AppColors.danger, fontSize: 13)),
                ),
              ],
              const SizedBox(height: 28),
              _submitting
                  ? const Center(child: CircularProgressIndicator())
                  : AppComponents.primaryButton(text: "Continue", onPressed: _continue),
            ],
          ),
        ),
      ),
    );
  }
}
