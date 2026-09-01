import 'package:ravelgo_user_app/components/platform_file_image.dart';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:ravelgo_user_app/components/basic_components.dart';
import 'package:ravelgo_user_app/theme/app_theme.dart';

/// License-photo step of the list-your-car flow.
/// The picked photo stays in local state; uploading it is the integration
/// point for the verification backend.
class PhotoLicensePage extends StatefulWidget {
  const PhotoLicensePage({super.key});

  @override
  State<PhotoLicensePage> createState() => _PhotoLicensePageState();
}

class _PhotoLicensePageState extends State<PhotoLicensePage> {
  final ImagePicker _picker = ImagePicker();
  XFile? _photo;

  Future<void> _pickPhoto() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image != null && mounted) {
      setState(() => _photo = image);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            AppComponents.header(context, "Photo with drivers license"),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Container(
                  decoration: AppComponents.cardDecoration(),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 180,
                        height: 180,
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          color: AppColors.border,
                        ),
                        child: _photo != null
                            ? localFileImage(_photo!.path, fit: BoxFit.cover)
                            : const Icon(Icons.badge_outlined, size: 56, color: AppColors.textMuted),
                      ),
                      const SizedBox(height: 20),
                      OutlinedButton(
                        onPressed: _pickPhoto,
                        style: OutlinedButton.styleFrom(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Text(_photo == null ? "Add a photo" : "Change photo"),
                      ),
                      const SizedBox(height: 20),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 20),
                        child: Text(
                          "Hold your driver’s license next to your face and take a clear photo, ensuring all information is readable.",
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            AppComponents.primaryButton(
                text: "Done",
                onPressed: () {
                  Navigator.pop(context, _photo);
                }),
          ],
        ),
      ),
    );
  }
}
