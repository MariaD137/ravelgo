import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:ravelgo_driver_app/services/api_client.dart';
import 'package:ravelgo_driver_app/services/driver_api.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';

/// One photo slot in the editor — either one of the vehicle's existing,
/// already-uploaded photos, or one the driver just picked on this screen.
class _PhotoItem {
  final String? existingUrl;
  final XFile? newFile;
  _PhotoItem.existing(String url)
      : existingUrl = url,
        newFile = null;
  _PhotoItem.newlyPicked(XFile file)
      : existingUrl = null,
        newFile = file;
}

const _maxVehiclePhotos = 7;

/// Add or edit a vehicle. Real backend-backed: POST /api/vehicles to add,
/// PATCH /api/vehicles/:id to edit. Pops `true` on success so the caller
/// reloads the real list rather than trusting a locally-fabricated record.
///
/// Up to 7 photos per vehicle. Newly picked photos are presigned + uploaded
/// to the public "assets" bucket (DriverApi.uploadToDocumentsBucket) only
/// once Save is pressed, so picking photos and backing out never leaves an
/// orphaned S3 object tied to a vehicle that was never actually
/// created/updated. On edit, the backend never hands raw S3 keys back to
/// the client, so removing an existing photo is done by its photoUrl and
/// adding a new one by its freshly presigned key — never a full replace.
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

  late final List<_PhotoItem> _photos =
      (widget.existing?.photoUrls ?? const []).map(_PhotoItem.existing).toList();

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

  Future<void> _pickPhotos() async {
    final remaining = _maxVehiclePhotos - _photos.length;
    if (remaining <= 0) return;
    final picked = await ImagePicker().pickMultiImage(imageQuality: 85, limit: remaining);
    if (picked.isEmpty || !mounted) return;
    setState(() => _photos.addAll(picked.take(remaining).map(_PhotoItem.newlyPicked)));
  }

  void _removePhoto(int index) => setState(() => _photos.removeAt(index));

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final newKeys = <String>[];
      for (final photo in _photos) {
        final file = photo.newFile;
        if (file == null) continue;
        final bytes = await file.readAsBytes();
        final lower = file.name.toLowerCase();
        final contentType = lower.endsWith('.png')
            ? 'image/png'
            : lower.endsWith('.webp')
                ? 'image/webp'
                : 'image/jpeg';
        final key = await DriverApi.uploadToDocumentsBucket(
          fileName: 'vehicle-photo-${DateTime.now().millisecondsSinceEpoch}-${newKeys.length}.${contentType.split('/').last}',
          contentType: contentType,
          bytes: bytes,
          bucket: 'assets',
        );
        newKeys.add(key);
      }

      if (_isEditing) {
        final keptUrls = _photos.map((p) => p.existingUrl).whereType<String>().toSet();
        final removedUrls = widget.existing!.photoUrls.where((u) => !keptUrls.contains(u)).toList();
        await DriverApi.updateVehicle(
          widget.existing!.id,
          brand: _brand.text.trim(),
          model: _model.text.trim(),
          colour: _colour.text.trim(),
          plateNumber: _plate.text.trim(),
          year: _year.text.trim(),
          isPrimary: _isPrimary,
          addPhotoKeys: newKeys,
          removePhotoUrls: removedUrls,
        );
      } else {
        await DriverApi.addVehicle(
          brand: _brand.text.trim(),
          model: _model.text.trim(),
          colour: _colour.text.trim(),
          plateNumber: _plate.text.trim(),
          year: _year.text.trim(),
          isPrimary: _isPrimary,
          photoKeys: newKeys,
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
            _photoGrid(),
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

  Widget _photoGrid() {
    final canAddMore = _photos.length < _maxVehiclePhotos;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Vehicle photos (${_photos.length}/$_maxVehiclePhotos)',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (var i = 0; i < _photos.length; i++) _photoTile(i),
            if (canAddMore) _addPhotoTile(),
          ],
        ),
        if (_photos.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'Add up to 7 photos of the vehicle.',
              style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
            ),
          ),
      ],
    );
  }

  Widget _photoTile(int index) {
    final photo = _photos[index];
    final image = photo.newFile != null
        ? Image.file(File(photo.newFile!.path), fit: BoxFit.cover, width: 100, height: 100)
        : Image.network(
            photo.existingUrl!,
            fit: BoxFit.cover,
            width: 100,
            height: 100,
            errorBuilder: (_, __, ___) => const ColoredBox(
              color: AppColors.surfaceElevated,
              child: Icon(Icons.directions_car, color: AppColors.textSecondary),
            ),
          );
    return SizedBox(
      width: 100,
      height: 100,
      child: Stack(
        children: [
          ClipRRect(borderRadius: BorderRadius.circular(10), child: image),
          Positioned(
            top: 4,
            right: 4,
            child: GestureDetector(
              onTap: _saving ? null : () => _removePhoto(index),
              child: const CircleAvatar(
                radius: 12,
                backgroundColor: Colors.black54,
                child: Icon(Icons.close, size: 14, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _addPhotoTile() {
    return GestureDetector(
      onTap: _saving ? null : _pickPhotos,
      child: Container(
        width: 100,
        height: 100,
        decoration: BoxDecoration(
          color: AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add_a_photo_outlined, color: AppColors.textSecondary),
              SizedBox(height: 4),
              Text('Add', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            ],
          ),
        ),
      ),
    );
  }
}
