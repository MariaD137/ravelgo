import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:ravelgo_driver_app/models/driver_onboarding_draft.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';
import 'package:ravelgo_driver_app/views/auth/verify_account_screen.dart';
import 'package:ravelgo_driver_app/widgets/pickable_upload_box.dart';

const _kRegistrationDocTitle = "Vehicle Registration (Car Papers)";
const _kRoadworthyDocTitle = "Roadworthiness Certificate";
const _kInsuranceDocTitle = "Insurance Certificate";

class VehicleInformationScreen extends StatefulWidget {
  const VehicleInformationScreen({super.key, required this.draft});

  final DriverOnboardingDraft draft;

  @override
  State<VehicleInformationScreen> createState() => _VehicleInformationScreenState();
}

class _VehicleInformationScreenState extends State<VehicleInformationScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _brand = TextEditingController(text: widget.draft.vehicleBrand);
  late final _model = TextEditingController(text: widget.draft.vehicleModel);
  late final _colour = TextEditingController(text: widget.draft.vehicleColour);
  late final _plate = TextEditingController(text: widget.draft.vehiclePlateNumber);
  late final _year = TextEditingController(text: widget.draft.vehicleYear);

  @override
  void dispose() {
    _brand.dispose();
    _model.dispose();
    _colour.dispose();
    _plate.dispose();
    _year.dispose();
    super.dispose();
  }

  void _continue() {
    if (!_formKey.currentState!.validate()) return;
    final draft = widget.draft
      ..vehicleBrand = _brand.text.trim()
      ..vehicleModel = _model.text.trim()
      ..vehicleColour = _colour.text.trim()
      ..vehiclePlateNumber = _plate.text.trim()
      ..vehicleYear = _year.text.trim();
    Navigator.push(context, MaterialPageRoute(builder: (context) => VerifyAccountScreen(draft: draft)));
  }

  String? _required(String? v) => (v == null || v.trim().isEmpty) ? 'Required' : null;

  @override
  Widget build(BuildContext context) {
    final draft = widget.draft;
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
                AppComponents.header(context, "Vehicle information"),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _brand,
                  decoration: const InputDecoration(labelText: "Brand", border: OutlineInputBorder()),
                  validator: _required,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _model,
                  decoration: const InputDecoration(labelText: "Model", border: OutlineInputBorder()),
                  validator: _required,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _colour,
                  decoration: const InputDecoration(labelText: "Colour", border: OutlineInputBorder()),
                  validator: _required,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _plate,
                  decoration: const InputDecoration(labelText: "Plate number", border: OutlineInputBorder()),
                  validator: _required,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _year,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: "Year", border: OutlineInputBorder()),
                  validator: (v) {
                    final value = v?.trim() ?? '';
                    if (value.isEmpty) return 'Required';
                    if (value.length < 4) return 'Enter a 4-digit year';
                    return null;
                  },
                ),
                const SizedBox(height: 24),
                PickableUploadBox(
                  label: "Upload vehicle registration (Car Papers)",
                  pickedFileName: draft.pickedFileFor(_kRegistrationDocTitle)?.name,
                  onPicked: (XFile file) => setState(() => draft.setPendingUpload(_kRegistrationDocTitle, file)),
                ),
                const SizedBox(height: 12),
                PickableUploadBox(
                  label: "Upload roadworthiness certificate",
                  pickedFileName: draft.pickedFileFor(_kRoadworthyDocTitle)?.name,
                  onPicked: (XFile file) => setState(() => draft.setPendingUpload(_kRoadworthyDocTitle, file)),
                ),
                const SizedBox(height: 12),
                PickableUploadBox(
                  label: "Upload insurance certificate",
                  pickedFileName: draft.pickedFileFor(_kInsuranceDocTitle)?.name,
                  onPicked: (XFile file) => setState(() => draft.setPendingUpload(_kInsuranceDocTitle, file)),
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
