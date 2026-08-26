import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class PickedImage {
  final Uint8List bytes;
  final String fileName;
  final String contentType;
  const PickedImage({required this.bytes, required this.fileName, required this.contentType});
}

String _contentTypeForExtension(String path) {
  final lower = path.toLowerCase();
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.webp')) return 'image/webp';
  return 'image/jpeg';
}

/// Shows a camera-vs-gallery choice, then hands back the picked image's
/// bytes/filename/contentType — or null if the driver cancels at any step.
/// Shared by the vehicle-photo and document-upload flows so the picker UI
/// (and its cancel handling) is written once.
Future<PickedImage?> pickImage(BuildContext context) async {
  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: Wrap(
        children: [
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Take a photo'),
            onTap: () => Navigator.pop(sheetContext, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Choose from gallery'),
            onTap: () => Navigator.pop(sheetContext, ImageSource.gallery),
          ),
        ],
      ),
    ),
  );
  if (source == null) return null;

  final picker = ImagePicker();
  final XFile? file = await picker.pickImage(source: source, imageQuality: 85);
  if (file == null) return null;

  final bytes = await file.readAsBytes();
  return PickedImage(bytes: bytes, fileName: file.name, contentType: _contentTypeForExtension(file.name));
}
