import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:signature/signature.dart';
import 'package:ravelgo_driver_app/services/api_client.dart';
import 'package:ravelgo_driver_app/services/driver_api.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';

/// Captures proof of delivery — a photo of the delivered package and the
/// recipient's signature — then marks the request DELIVERED. The backend
/// rejects the DELIVERED transition without both, so this screen is the only
/// way a driver can complete a delivery.
class DeliveryProofScreen extends StatefulWidget {
  final CourierRequest request;
  const DeliveryProofScreen({super.key, required this.request});

  @override
  State<DeliveryProofScreen> createState() => _DeliveryProofScreenState();
}

class _DeliveryProofScreenState extends State<DeliveryProofScreen> {
  final SignatureController _signatureController = SignatureController(penStrokeWidth: 3, penColor: Colors.black);
  XFile? _photo;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _signatureController.dispose();
    super.dispose();
  }

  Future<void> _takePhoto() async {
    final photo = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 80);
    if (photo == null || !mounted) return;
    setState(() => _photo = photo);
  }

  bool get _canSubmit => _photo != null && _signatureController.isNotEmpty && !_submitting;

  Future<void> _submit() async {
    final photo = _photo;
    if (photo == null || _signatureController.isEmpty) return;

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final signatureBytes = await _signatureController.toPngBytes();
      if (signatureBytes == null) throw Exception('Could not capture the signature — try again.');
      final photoBytes = await photo.readAsBytes();

      final deliveryPhotoKey = await DriverApi.uploadToDocumentsBucket(
        fileName: 'delivery-photo.jpg',
        contentType: 'image/jpeg',
        bytes: photoBytes,
      );
      final recipientSignatureKey = await DriverApi.uploadToDocumentsBucket(
        fileName: 'recipient-signature.png',
        contentType: 'image/png',
        bytes: signatureBytes,
      );

      final updated = await DriverApi.updateDeliveryStatus(
        widget.request.id,
        'DELIVERED',
        finalFare: widget.request.estimatedFare,
        deliveryPhotoKey: deliveryPhotoKey,
        recipientSignatureKey: recipientSignatureKey,
      );
      if (!mounted) return;
      Navigator.of(context).pop(updated);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e is ApiException ? e.message : 'Could not complete the delivery — try again.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Confirm delivery')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('1. Photo of the delivered package', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 10),
          if (_photo != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(File(_photo!.path), height: 180, width: double.infinity, fit: BoxFit.cover),
            ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _submitting ? null : _takePhoto,
            icon: const Icon(Icons.camera_alt_outlined),
            label: Text(_photo == null ? 'Take photo' : 'Retake photo'),
          ),
          const SizedBox(height: 24),
          const Text('2. Recipient signature', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 10),
          Container(
            height: 200,
            decoration: BoxDecoration(border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(12)),
            child: Signature(controller: _signatureController, backgroundColor: Colors.white),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _submitting ? null : () => setState(_signatureController.clear),
              child: const Text('Clear signature'),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: AppColors.danger)),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: AppComponents.primaryButton(
              text: _submitting ? 'Submitting…' : 'Confirm delivery',
              onPressed: _canSubmit ? _submit : null,
            ),
          ),
        ],
      ),
    );
  }
}
