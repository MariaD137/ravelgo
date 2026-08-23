import 'package:flutter/material.dart';
import 'package:ravelgo_driver_app/models/driver_onboarding_draft.dart';
import 'package:ravelgo_driver_app/services/api/api_client.dart';
import 'package:ravelgo_driver_app/services/driver_session.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';
import 'package:ravelgo_driver_app/views/shell/driver_shell.dart';

/// The real onboarding submission step. There is no Cognito-backed OTP/
/// verification capability to check a code against yet, so this no longer
/// shows a fake 6-digit code — instead it reviews what was entered and, on
/// submit, makes the real backend calls (POST /drivers/me is required;
/// preferences, vehicle, and document uploads are attempted best-effort and
/// never block getting into the app, since each can be completed later from
/// Ride Preferences / My Vehicles / My Documents).
class VerifyAccountScreen extends StatefulWidget {
  const VerifyAccountScreen({super.key, required this.draft});

  final DriverOnboardingDraft draft;

  @override
  State<VerifyAccountScreen> createState() => _VerifyAccountScreenState();
}

class _VerifyAccountScreenState extends State<VerifyAccountScreen> {
  bool _submitting = false;
  String? _error;

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    final draft = widget.draft;
    final session = DriverSession.instance;

    try {
      await session.driverApi.createMyProfile(
        firstName: draft.firstName,
        lastName: draft.lastName,
        email: draft.email,
        phoneNumber: draft.phoneNumber,
        preferredLanguage: draft.preferredLanguage,
      );
    } on ApiException catch (err) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = err.message;
      });
      return;
    }

    // Everything below this point is best-effort: the Driver row now
    // exists (the one thing that must succeed to proceed), so a failure in
    // preferences/vehicle/documents shouldn't trap the driver on this
    // screen — each can be completed later from the shell.
    if (draft.quietModePreferred) {
      try {
        await session.driverApi.updatePreferences(quietModePreferred: true);
      } on ApiException {
        // Non-fatal — can be changed later from Ride Preferences.
      }
    }
    if (draft.hasVehicleInfo) {
      try {
        await session.vehicleApi.create(
          brand: draft.vehicleBrand,
          model: draft.vehicleModel,
          colour: draft.vehicleColour,
          plateNumber: draft.vehiclePlateNumber,
          year: draft.vehicleYear,
          isPrimary: true,
        );
      } on ApiException {
        // Non-fatal — can be added later from My Vehicles.
      }
    }
    var uploadFailures = 0;
    for (final upload in draft.pendingUploads) {
      try {
        final bytes = await upload.file.readAsBytes();
        await session.documentApi.uploadAndRegister(
          title: upload.title,
          bytes: bytes,
          fileName: upload.file.name,
          contentType: upload.file.mimeType ?? 'image/jpeg',
        );
      } on ApiException {
        uploadFailures++;
      }
    }

    if (!mounted) return;
    setState(() => _submitting = false);
    if (uploadFailures > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$uploadFailures document(s) could not be uploaded — you can retry from My Documents.')),
      );
    }
    _navigateToDriverShell();
  }

  void _navigateToDriverShell() {
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => const DriverShell()),
      (route) => false,
    );
  }

  Widget _summaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 70, child: Text(label, style: const TextStyle(fontSize: 12, color: Colors.black54))),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
        ],
      ),
    );
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
              AppComponents.header(context, "Submit your application"),
              const SizedBox(height: 20),
              const Text(
                "Review your details, then submit your application to RavelGo.",
                style: TextStyle(fontSize: 14, color: Colors.black54),
              ),
              const SizedBox(height: 20),
              _summaryRow("Name", "${draft.firstName} ${draft.lastName}"),
              _summaryRow("Email", draft.email),
              _summaryRow("Phone", draft.phoneNumber),
              if (draft.hasVehicleInfo)
                _summaryRow("Vehicle", "${draft.vehicleBrand} ${draft.vehicleModel} · ${draft.vehiclePlateNumber}"),
              if (draft.pendingUploads.isNotEmpty)
                _summaryRow("Documents", "${draft.pendingUploads.length} file(s) ready to upload"),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
              ],
              const SizedBox(height: 24),
              const Text(
                "Your application will be reviewed within 24-48 hours. You can go online as soon as your documents are approved.",
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
              const SizedBox(height: 12),
              AppComponents.primaryButton(
                text: _submitting ? "Submitting…" : (_error != null ? "Retry" : "Submit application"),
                onPressed: _submitting ? null : _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
