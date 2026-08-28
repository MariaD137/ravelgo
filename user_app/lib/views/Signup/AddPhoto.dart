import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:ravelgo_user_app/views/bottommenu/BottomNavigationView.dart';
import 'package:ravelgo_user_app/theme/app_theme.dart';

/// Final rider profile-setup step: an optional profile photo, then home.
/// The photo stays in local state; uploading it is the integration point
/// for the future profile/storage backend.
class AddPhotoScreen extends StatefulWidget {
  const AddPhotoScreen({super.key});

  @override
  State<AddPhotoScreen> createState() => _AddPhotoScreenState();
}

class _AddPhotoScreenState extends State<AddPhotoScreen> {
  final ImagePicker _picker = ImagePicker();
  XFile? _photo;

  Future<void> _pickPhoto() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image != null && mounted) {
      setState(() => _photo = image);
    }
  }

  void _finish() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => BottomNavigationView()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Text('Set up your profile', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 18),
            Container(
              decoration: BoxDecoration(color: AppColors.surfaceElevated, borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.all(18),
              child: Column(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      height: 180,
                      width: 180,
                      child: _photo != null
                          ? Image.file(File(_photo!.path), fit: BoxFit.cover)
                          : Container(
                              color: AppColors.surfaceElevated,
                              child: const Center(child: Icon(Icons.person, size: 60, color: AppColors.textMuted)),
                            ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: _pickPhoto,
                    child: Text(_photo == null ? 'Add a photo' : 'Change photo'),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'A clear photo of yourself helps drivers identify you at pickup. You can also add one later from your account.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _finish,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(_photo == null ? 'Skip for now' : 'Finish'),
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }
}
