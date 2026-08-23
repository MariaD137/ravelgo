import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../theme/app_theme.dart';

/// A real, tappable version of [AppComponents.uploadBox]: lets the driver
/// pick an actual image from their device (via image_picker, already a
/// dependency) and reports it back through [onPicked]. This does not upload
/// anything itself — the caller (an onboarding screen) holds the picked
/// file in a [DriverOnboardingDraft] until the real upload happens on the
/// final submission step, once a Driver row exists to attribute it to.
class PickableUploadBox extends StatelessWidget {
  const PickableUploadBox({super.key, required this.label, required this.onPicked, this.pickedFileName});

  final String label;
  final String? pickedFileName;
  final ValueChanged<XFile> onPicked;

  Future<void> _pick(BuildContext context) async {
    try {
      final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
      if (picked != null) onPicked(picked);
    } catch (err) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not open the photo library: $err')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final picked = pickedFileName != null;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => _pick(context),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: picked ? AppColors.success : AppColors.border),
          color: Colors.white,
        ),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(8)),
              child: Icon(picked ? Icons.check_circle_outline : Icons.upload_file_outlined, color: picked ? AppColors.success : null),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(fontSize: 13)),
                  if (picked)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(pickedFileName!, style: const TextStyle(fontSize: 11, color: AppColors.success)),
                    ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 18),
          ],
        ),
      ),
    );
  }
}
