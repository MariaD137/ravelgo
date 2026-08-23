import 'package:image_picker/image_picker.dart';

/// A document the driver picked during onboarding (driver_information_screen
/// / vehicle_information_screen's upload boxes) but that hasn't been
/// uploaded to the backend yet — that happens for real, all at once, on the
/// final "Submit application" step (verify_account_screen), once
/// POST /drivers/me has created the Driver row these uploads are
/// attributed to.
class PendingUpload {
  const PendingUpload({required this.title, required this.file});

  final String title;
  final XFile file;
}

/// Carries the driver's onboarding answers across
/// create_account_screen -> add_photo_screen -> driver_information_screen ->
/// vehicle_information_screen -> verify_account_screen, so the real backend
/// submission (POST /drivers/me, POST /vehicles, document uploads) happens
/// once, on the final screen, with the complete picture — rather than each
/// screen submitting a partial profile piecemeal.
class DriverOnboardingDraft {
  String firstName = '';
  String lastName = '';
  String email = '';
  String phoneNumber = '';

  String preferredLanguage = 'English';
  bool quietModePreferred = false;

  String vehicleBrand = '';
  String vehicleModel = '';
  String vehicleColour = '';
  String vehiclePlateNumber = '';
  String vehicleYear = '';

  bool get hasVehicleInfo =>
      vehicleBrand.isNotEmpty &&
      vehicleModel.isNotEmpty &&
      vehicleColour.isNotEmpty &&
      vehiclePlateNumber.isNotEmpty &&
      vehicleYear.isNotEmpty;

  final List<PendingUpload> pendingUploads = [];

  void setPendingUpload(String title, XFile file) {
    pendingUploads.removeWhere((u) => u.title == title);
    pendingUploads.add(PendingUpload(title: title, file: file));
  }

  XFile? pickedFileFor(String title) {
    for (final upload in pendingUploads) {
      if (upload.title == title) return upload.file;
    }
    return null;
  }
}
