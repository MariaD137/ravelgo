import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:ravelgo_driver_app/services/api_client.dart';
import 'package:ravelgo_driver_app/services/driver_api.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';

/// Add or edit a vehicle. Real backend-backed: POST /api/vehicles to add,
/// PATCH /api/vehicles/:id to edit. Pops `true` on success so the caller
/// reloads the real list rather than trusting a locally-fabricated record.
///
/// The photo (if picked) is presigned + uploaded to the public "assets"
/// bucket (DriverApi.uploadToDocumentsBucket) only once Save is pressed, so
/// picking a photo and backing out never leaves an orphaned S3 object tied
/// to a vehicle that was never actually created/updated.
class AddVehicleScreen extends StatefulWidget {
  final Vehicle? existing;
  const AddVehicleScreen({super.key, this.existing});

  @override
  State<AddVehicleScreen> createState() => _AddVehicleScreenState();
}

class _AddVehicleScreenState extends State<AddVehicleScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _brand = TextEditingController(text: widget.existing?.brand ?? '');
  late final _model = TextEditingController(text: widget.existing?.model ?? '');
  late final _colour = TextEditingController(text: widget.existing?.colour ?? '');
  late final _plate = TextEditingController(text: widget.existing?.plateNumber ?? '');
  late final _year = TextEditingController(text: widget.existing?.year ?? '');
  late bool _isPrimary = widget.existing?.isPrimary ?? false;
  bool _saving = false;

  XFile? _newPhoto;
  bool get _hasPhoto => _newPhoto != null || widget.existing?.photoUrl != null;

  bool get _isEditing => widget.existing != null;

  @override
  void dispose() {
    _brand.dispose();
    _model.dispose();
    _colour.dispose();
    _plate.dispose();
    _year.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final photo = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (photo == null || !mounted) return;
    setState(() => _newPhoto = photo);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      String? photoKey;
      final photo = _newPhoto;
      if (photo != null) {
        final bytes = await photo.readAsBytes();
        final lower = photo.name.toLowerCase();
        final contentType = lower.endsWith('.png')
            ? 'image/png'
            : lower.endsWith('.webp')
                ? 'image/webp'
                : 'image/jpeg';
        photoKey = await DriverApi.uploadToDocumentsBucket(
          fileName: 'vehicle-photo-${DateTime.now().millisecondsSinceEpoch}.${contentType.split('/').last}',
          contentType: contentType,
          bytes: bytes,
          bucket: 'assets',
        );
      }

      if (_isEditing) {
        await DriverApi.updateVehicle(
          widget.existing!.id,
          brand: _brand.text.trim(),
          model: _model.text.trim(),
          colour: _colour.text.trim(),
          plateNumber: _plate.text.trim(),
          year: _year.text.trim(),
          isPrimary: _isPrimary,
          photoKey: photoKey,
        );
      } else {
        await DriverApi.addVehicle(
          brand: _brand.text.trim(),
          model: _model.text.trim(),
          colour: _colour.text.trim(),
          plateNumber: _plate.text.trim(),
          year: _year.text.trim(),
          isPrimary: _isPrimary,
          photoKey: photoKey,
        );
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      final message = e is ApiException ? e.message : 'Could not save this vehicle.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? "Edit Vehicle" : "Add Vehicle")),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _photoPicker(),
            const SizedBox(height: 20),
            TextFormField(
              controller: _brand,
              decoration: const InputDecoration(labelText: "Brand", border: OutlineInputBorder()),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter a brand' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _model,
              decoration: const InputDecoration(labelText: "Model", border: OutlineInputBorder()),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter a model' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _colour,
              decoration: const InputDecoration(labelText: "Colour", border: OutlineInputBorder()),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter a colour' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _plate,
              decoration: const InputDecoration(labelText: "Plate number", border: OutlineInputBorder()),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter a plate number' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _year,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: "Year", border: OutlineInputBorder()),
              validator: (v) => (v == null || v.trim().length < 4) ? 'Enter a valid year' : null,
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text("Primary vehicle"),
              value: _isPrimary,
              onChanged: (v) => setState(() => _isPrimary = v),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppColors.surfaceElevated, borderRadius: BorderRadius.circular(10)),
              child: const Text(
                "Upload this vehicle's registration and other papers from My Documents once it's saved.",
                style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
              ),
            ),
            const SizedBox(height: 28),
            AppComponents.primaryButton(
              text: _saving ? "Saving…" : "Save vehicle",
              onPressed: _saving ? null : _save,
            ),
          ],
        ),
      ),
    );
  }

  Widget _photoPicker() {
    return GestureDetector(
      onTap: _saving ? null : _pickPhoto,
      child: Container(
        height: 160,
        width: double.infinity,
        decoration: BoxDecoration(
          color: AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: _hasPhoto ? _photoPreview() : _photoPlaceholder(),
      ),
    );
  }

  Widget _photoPreview() {
    final overlay = Positioned(
      right: 8,
      bottom: 8,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.edit, size: 14, color: Colors.white),
            SizedBox(width: 4),
            Text('Change photo', style: TextStyle(fontSize: 12, color: Colors.white)),
          ],
        ),
      ),
    );
    final image = _newPhoto != null
        ? Image.file(File(_newPhoto!.path), fit: BoxFit.cover, width: double.infinity, height: double.infinity)
        : Image.network(
            widget.existing!.photoUrl!,
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            errorBuilder: (_, __, ___) => _photoPlaceholder(),
          );
    return Stack(fit: StackFit.expand, children: [image, overlay]);
  }

  Widget _photoPlaceholder() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.add_a_photo_outlined, color: AppColors.textSecondary),
          SizedBox(height: 6),
          Text('Add a photo of the vehicle', style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}
