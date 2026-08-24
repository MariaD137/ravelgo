import 'package:flutter/material.dart';
import 'package:ravelgo_driver_app/models/document_item.dart';
import 'package:ravelgo_driver_app/models/vehicle.dart';
import 'package:ravelgo_driver_app/services/driver_api.dart';
import 'package:ravelgo_driver_app/services/image_picker_helper.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';
import 'package:ravelgo_driver_app/views/vehicles/edit_vehicle_screen.dart';
import 'package:url_launcher/url_launcher.dart';

enum _LoadState { loading, loaded, error }

// Vehicle-scoped document types only — driver-level ones (license,
// background check, proof of address) live on MyDocumentsScreen instead.
const _vehicleDocumentTypes = [
  DriverDocumentType.vehicleRegistration,
  DriverDocumentType.insurance,
  DriverDocumentType.inspection,
  DriverDocumentType.roadworthiness,
];

class VehicleDetailScreen extends StatefulWidget {
  final String vehicleId;
  final DriverApi api;
  const VehicleDetailScreen({super.key, required this.vehicleId, required this.api});

  @override
  State<VehicleDetailScreen> createState() => _VehicleDetailScreenState();
}

class _VehicleDetailScreenState extends State<VehicleDetailScreen> {
  _LoadState _state = _LoadState.loading;
  Vehicle? _vehicle;
  List<DriverDocument> _documents = [];
  String _errorMessage = "Unable to load this vehicle";
  bool _busy = false; // photo upload / delete / resubmit / deactivate in flight

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _state = _LoadState.loading);
    try {
      final results = await Future.wait([
        widget.api.fetchVehicle(widget.vehicleId),
        widget.api.fetchDocuments(vehicleId: widget.vehicleId),
      ]);
      if (!mounted) return;
      setState(() {
        _vehicle = results[0] as Vehicle;
        _documents = results[1] as List<DriverDocument>;
        _state = _LoadState.loaded;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e is DriverApiException ? e.message : "Unable to load this vehicle";
        _state = _LoadState.error;
      });
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _addPhoto() async {
    final picked = await pickImage(context);
    if (picked == null || !mounted) return;

    final photoType = await showModalBottomSheet<VehiclePhotoType>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: VehiclePhotoType.values
              .map((type) => ListTile(
                    title: Text(vehiclePhotoTypeLabel(type)),
                    onTap: () => Navigator.pop(sheetContext, type),
                  ))
              .toList(),
        ),
      ),
    );
    if (photoType == null || !mounted) return;

    setState(() => _busy = true);
    try {
      await widget.api.uploadVehiclePhoto(
        vehicleId: widget.vehicleId,
        bytes: picked.bytes,
        fileName: picked.fileName,
        contentType: picked.contentType,
        photoType: photoType,
      );
      await _load();
    } catch (e) {
      _showError(e is DriverApiException ? e.message : "Upload failed");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deletePhoto(VehiclePhoto photo) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text("Remove photo?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text("Cancel")),
          TextButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text("Remove")),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      await widget.api.deleteVehiclePhoto(widget.vehicleId, photo.id);
      await _load();
    } catch (e) {
      _showError(e is DriverApiException ? e.message : "Unable to remove this photo");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _uploadVehicleDocument(DriverDocumentType type, {bool isReplace = false}) async {
    final picked = await pickImage(context);
    if (picked == null || !mounted) return;

    setState(() => _busy = true);
    try {
      final existing = _documents.where((d) => d.documentType == type).toList();
      if (isReplace && existing.isNotEmpty && existing.first.status == DocumentStatus.rejected) {
        await widget.api.resubmitDocument(
          documentId: existing.first.id,
          bytes: picked.bytes,
          fileName: picked.fileName,
          contentType: picked.contentType,
        );
      } else {
        await widget.api.uploadDocument(
          bytes: picked.bytes,
          fileName: picked.fileName,
          contentType: picked.contentType,
          title: driverDocumentTypeLabel(type),
          documentType: type,
          vehicleId: widget.vehicleId,
        );
      }
      await _load();
    } catch (e) {
      _showError(e is DriverApiException ? e.message : "Upload failed");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _viewDocument(DriverDocument doc) async {
    try {
      final url = await widget.api.fetchDocumentViewUrl(doc.id);
      final uri = Uri.parse(url);
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        _showError("Unable to open this document");
      }
    } catch (e) {
      _showError(e is DriverApiException ? e.message : "Unable to open this document");
    }
  }

  Future<void> _resubmitVehicle() async {
    setState(() => _busy = true);
    try {
      await widget.api.resubmitVehicle(widget.vehicleId);
      await _load();
    } catch (e) {
      _showError(e is DriverApiException ? e.message : "Unable to resubmit this vehicle");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deactivate() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text("Remove this vehicle?"),
        content: const Text("This vehicle will no longer be usable for trips. You can contact support to reactivate it later."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text("Cancel")),
          TextButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text("Remove")),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      await widget.api.deactivateVehicle(widget.vehicleId);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      _showError(e is DriverApiException ? e.message : "Unable to remove this vehicle");
      if (mounted) setState(() => _busy = false);
    }
  }

  (Color, String, String?) _verificationInfo(Vehicle v) {
    switch (v.verificationStatus) {
      case VehicleVerificationStatus.approved:
        return (AppColors.success, "Approved", "This vehicle is verified and can be used for trips.");
      case VehicleVerificationStatus.pending:
        return (Colors.orange, "Pending review", "Our team is reviewing this vehicle. This usually takes 1-2 business days.");
      case VehicleVerificationStatus.rejected:
        return (AppColors.danger, "Rejected", v.verificationReason);
      case VehicleVerificationStatus.resubmissionRequired:
        return (Colors.orange, "Needs resubmission", v.verificationReason);
    }
  }

  Color _docStatusColor(DocumentStatus s) {
    switch (s) {
      case DocumentStatus.approved:
        return AppColors.success;
      case DocumentStatus.pending:
        return AppColors.primaryDark;
      case DocumentStatus.expiringSoon:
        return Colors.orange;
      case DocumentStatus.rejected:
        return AppColors.danger;
      case DocumentStatus.notUploaded:
        return Colors.grey;
    }
  }

  String _docStatusLabel(DocumentStatus s) {
    switch (s) {
      case DocumentStatus.approved:
        return "Approved";
      case DocumentStatus.pending:
        return "Under review";
      case DocumentStatus.expiringSoon:
        return "Expiring soon";
      case DocumentStatus.rejected:
        return "Rejected";
      case DocumentStatus.notUploaded:
        return "Not uploaded";
    }
  }

  Widget _buildPhotos(Vehicle vehicle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            AppComponents.sectionTitle("Photos"),
            TextButton.icon(
              onPressed: _busy ? null : _addPhoto,
              icon: const Icon(Icons.add_a_photo_outlined, size: 18),
              label: const Text("Add"),
            ),
          ],
        ),
        if (vehicle.photos.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: AppComponents.cardDecoration(),
            child: const Text("No photos yet. Add clear photos of the front, rear, and sides.", style: TextStyle(fontSize: 12.5, color: Colors.black54)),
          )
        else
          SizedBox(
            height: 100,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: vehicle.photos.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final photo = vehicle.photos[i];
                return Stack(
                  children: [
                    Container(
                      width: 100,
                      height: 100,
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), color: AppColors.background),
                      child: photo.url != null
                          ? Image.network(photo.url!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined))
                          : const Icon(Icons.image_outlined),
                    ),
                    Positioned(
                      top: 4,
                      left: 4,
                      child: AppComponents.badge(vehiclePhotoTypeLabel(photo.photoType)),
                    ),
                    Positioned(
                      top: 2,
                      right: 2,
                      child: GestureDetector(
                        onTap: _busy ? null : () => _deletePhoto(photo),
                        child: const CircleAvatar(radius: 12, backgroundColor: Colors.black54, child: Icon(Icons.close, size: 14, color: Colors.white)),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildDocuments() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppComponents.sectionTitle("Vehicle documents"),
        ..._vehicleDocumentTypes.map((type) {
          final matches = _documents.where((d) => d.documentType == type).toList();
          final doc = matches.isEmpty ? null : matches.first;
          final status = doc?.status ?? DocumentStatus.notUploaded;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: AppComponents.cardDecoration(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(driverDocumentTypeLabel(type), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5))),
                      AppComponents.badge(_docStatusLabel(status), color: _docStatusColor(status)),
                    ],
                  ),
                  if (status == DocumentStatus.rejected && doc?.rejectionReason != null) ...[
                    const SizedBox(height: 6),
                    Text(doc!.rejectionReason!, style: const TextStyle(fontSize: 12, color: AppColors.danger)),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      if (doc != null && doc.hasFile)
                        TextButton(onPressed: _busy ? null : () => _viewDocument(doc), child: const Text("View")),
                      TextButton(
                        onPressed: _busy ? null : () => _uploadVehicleDocument(type, isReplace: status == DocumentStatus.rejected),
                        child: Text(doc == null ? "Upload" : "Replace"),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildLoaded(Vehicle vehicle) {
    final (statusColor, statusLabel, statusDetail) = _verificationInfo(vehicle);
    final canResubmit = vehicle.verificationStatus == VehicleVerificationStatus.rejected ||
        vehicle.verificationStatus == VehicleVerificationStatus.resubmissionRequired;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: AppComponents.cardDecoration(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("${vehicle.brand} ${vehicle.model}", style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                    AppComponents.badge(statusLabel, color: statusColor),
                  ],
                ),
                const SizedBox(height: 4),
                Text("${vehicle.colour} · ${vehicle.plateNumber} · ${vehicle.year}", style: const TextStyle(fontSize: 13, color: Colors.black54)),
                if (vehicle.vin != null) Text("VIN: ${vehicle.vin}", style: const TextStyle(fontSize: 12, color: Colors.black45)),
                Text(vehicleTypeLabel(vehicle.vehicleType), style: const TextStyle(fontSize: 12, color: Colors.black45)),
                if (statusDetail != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8)),
                    child: Text(statusDetail, style: TextStyle(fontSize: 12.5, color: statusColor)),
                  ),
                ],
                if (!vehicle.isActive) ...[
                  const SizedBox(height: 10),
                  const Text("This vehicle has been removed and is no longer active.", style: TextStyle(fontSize: 12.5, color: Colors.black54)),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),
          _buildPhotos(vehicle),
          const SizedBox(height: 20),
          _buildDocuments(),
          const SizedBox(height: 24),
          if (canResubmit)
            AppComponents.primaryButton(
              text: _busy ? "Resubmitting..." : "Resubmit for review",
              onPressed: _busy ? null : _resubmitVehicle,
            ),
          if (vehicle.isActive) ...[
            const SizedBox(height: 12),
            AppComponents.outlineButton(
              text: "Remove vehicle",
              color: AppColors.danger,
              onPressed: _busy ? null : _deactivate,
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // No pop-result plumbing needed to keep the vehicle list fresh — see
    // VehicleListScreen._openDetail, which reloads unconditionally after
    // returning from this screen rather than relying on a returned flag.
    return Scaffold(
      appBar: AppBar(
        title: const Text("Vehicle"),
        actions: [
          if (_state == _LoadState.loaded && _vehicle != null)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              onPressed: () async {
                final edited = await Navigator.push<bool>(
                  context,
                  MaterialPageRoute(builder: (_) => EditVehicleScreen(vehicle: _vehicle!, api: widget.api)),
                );
                if (edited == true) {
                  _load();
                }
              },
            ),
        ],
      ),
      body: switch (_state) {
        _LoadState.loading => const Center(child: CircularProgressIndicator()),
        _LoadState.error => Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text("Unable to load this vehicle", style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Text(_errorMessage, style: const TextStyle(fontSize: 12.5, color: Colors.black54), textAlign: TextAlign.center),
                const SizedBox(height: 16),
                AppComponents.outlineButton(text: "Try again", onPressed: _load),
              ],
            ),
          ),
        _LoadState.loaded => _buildLoaded(_vehicle!),
      },
    );
  }
}
