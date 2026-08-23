import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:ravelgo_driver_app/models/driver_onboarding_draft.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';
import 'package:ravelgo_driver_app/views/auth/vehicle_information_screen.dart';
import 'package:ravelgo_driver_app/widgets/pickable_upload_box.dart';

const _kLicenseDocTitle = "Driver's License";
const _kBackgroundCheckDocTitle = "Background Check Consent";

class DriverInformationScreen extends StatefulWidget {
  const DriverInformationScreen({super.key, required this.draft});

  final DriverOnboardingDraft draft;

  @override
  State<DriverInformationScreen> createState() => _DriverInformationScreenState();
}

class _DriverInformationScreenState extends State<DriverInformationScreen> {
  // Driver's license number and years of experience have no field on the
  // Driver model yet — kept as free-form UI input (consistent with not
  // deleting existing product structure just because the backend can't
  // persist it yet), but intentionally never sent anywhere.
  final _licenseNumber = TextEditingController();
  final _yearsExperience = TextEditingController();

  @override
  void dispose() {
    _licenseNumber.dispose();
    _yearsExperience.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final draft = widget.draft;
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
              TextField(
                controller: _licenseNumber,
                decoration: const InputDecoration(labelText: "Driver's License Number", border: OutlineInputBorder()),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _yearsExperience,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: "Years of driving experience", border: OutlineInputBorder()),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: draft.preferredLanguage,
                decoration: const InputDecoration(labelText: "Preferred language", border: OutlineInputBorder()),
                items: const ["English", "French", "Yoruba", "Igbo", "Hausa"]
                    .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                    .toList(),
                onChanged: (v) => setState(() => draft.preferredLanguage = v ?? draft.preferredLanguage),
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text("Prefer quiet rides (no small talk)"),
                value: draft.quietModePreferred,
                onChanged: (v) => setState(() => draft.quietModePreferred = v),
              ),
              const SizedBox(height: 24),
              PickableUploadBox(
                label: "Upload driver's license",
                pickedFileName: draft.pickedFileFor(_kLicenseDocTitle)?.name,
                onPicked: (XFile file) => setState(() => draft.setPendingUpload(_kLicenseDocTitle, file)),
              ),
              const SizedBox(height: 12),
              PickableUploadBox(
                label: "Upload background check consent",
                pickedFileName: draft.pickedFileFor(_kBackgroundCheckDocTitle)?.name,
                onPicked: (XFile file) => setState(() => draft.setPendingUpload(_kBackgroundCheckDocTitle, file)),
              ),
              const SizedBox(height: 28),
              AppComponents.primaryButton(
                text: "Continue",
                onPressed: () {
                  Navigator.push(context, MaterialPageRoute(builder: (context) => VehicleInformationScreen(draft: draft)));
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
