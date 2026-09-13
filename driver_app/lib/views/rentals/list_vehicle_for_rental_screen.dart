import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:ravelgo_driver_app/services/api_client.dart';
import 'package:ravelgo_driver_app/services/driver_api.dart';
import 'package:ravelgo_driver_app/services/places_api.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';
import 'package:ravelgo_driver_app/views/places/place_search_screen.dart';
import 'package:ravelgo_driver_app/views/vehicles/add_vehicle_screen.dart';

class ListVehicleForRentalScreen extends StatefulWidget {
  const ListVehicleForRentalScreen({super.key});

  @override
  State<ListVehicleForRentalScreen> createState() => _ListVehicleForRentalScreenState();
}

class _ListVehicleForRentalScreenState extends State<ListVehicleForRentalScreen> {
  final _rateController = TextEditingController();
  final _locationController = TextEditingController();

  bool _loadingVehicles = true;
  bool _submitting = false;
  String? _vehiclesError;
  String? _formError;
  List<Vehicle> _vehicles = const [];
  String? _vehicleId;
  // Set only when the driver picks a real address via the Places-backed
  // search below — never guessed, so a listing created before this existed
  // (or without picking) simply has no coordinates (see PRD audit: rentals
  // had zero location/geocoding integration before this).
  PlaceLocation? _pickedLocation;

  // Real upload via the same presign -> S3 PUT -> POST /api/documents
  // pipeline "My Documents" uses (DriverApi.uploadDocument) — never a fake
  // upload that only changes the UI. Recorded as a DriverDocument (the
  // existing driver-level document model; RentalListing itself has no
  // document field of its own) titled with the vehicle's plate number so an
  // admin reviewing it can tell which vehicle it's for.
  bool _uploadingDocument = false;
  DriverDocument? _uploadedDocument;
  String? _documentError;

  @override
  void initState() {
    super.initState();
    _loadVehicles();
  }

  @override
  void dispose() {
    _rateController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  Vehicle? get _selectedVehicle {
    for (final v in _vehicles) {
      if (v.id == _vehicleId) return v;
    }
    return null;
  }

  // Enables Submit only once every requirement is actually met — the
  // backend remains the authoritative check (driver ACTIVE, vehicle
  // ownership, no existing active listing for this vehicle), this is purely
  // so the button can't be tapped at all on an obviously incomplete form.
  bool get _canSubmit {
    if (_submitting || _vehicles.isEmpty || _vehicleId == null || _uploadingDocument) return false;
    final rate = double.tryParse(_rateController.text.replaceAll(',', '').trim());
    if (rate == null || rate <= 0) return false;
    if (_locationController.text.trim().isEmpty) return false;
    if (_uploadedDocument == null) return false;
    return true;
  }

  Future<void> _loadVehicles() async {
    setState(() {
      _loadingVehicles = true;
      _vehiclesError = null;
    });
    try {
      final v = await DriverApi.myVehicles();
      if (!mounted) return;
      setState(() {
        _vehicles = v;
        _vehicleId = v.isNotEmpty ? v.first.id : null;
        _loadingVehicles = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _vehiclesError = e is ApiException && e.statusCode == 403
            ? 'Your account isn\'t set up as a driver yet.'
            : e is ApiException
                ? e.message
                : 'Could not load your vehicles. Please try again.';
        _loadingVehicles = false;
      });
    }
  }

  /// Opens the same real, Places-backed address search the rider app's ride
  /// booking and "Send a Package" flows use, so a rental listing's location
  /// resolves to an actual verified address (with coordinates) instead of
  /// whatever free text a driver happens to type.
  Future<void> _pickLocation() async {
    final place = await Navigator.of(context).push<PlaceLocation>(
      MaterialPageRoute(
        builder: (_) => const PlaceSearchScreen(title: 'Pickup location', hint: 'Search for a pickup location'),
      ),
    );
    if (place == null || !mounted) return;
    setState(() {
      _pickedLocation = place;
      _locationController.text = place.address;
    });
  }

  /// Picks an image of the ownership/insurance document and uploads it for
  /// real via the same pipeline MyDocumentsScreen uses: presign -> PUT the
  /// bytes straight to S3 -> POST /api/documents to record the metadata.
  /// Tapping again after a failure simply retries the same flow.
  Future<void> _pickAndUploadDocument() async {
    final vehicle = _selectedVehicle;
    if (vehicle == null) return;

    final XFile? picked;
    try {
      picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not open picker: $e')));
      return;
    }
    if (picked == null || !mounted) return;

    setState(() {
      _uploadingDocument = true;
      _documentError = null;
    });
    try {
      final bytes = await picked.readAsBytes();
      final lower = picked.name.toLowerCase();
      final contentType = picked.mimeType ??
          (lower.endsWith('.png')
              ? 'image/png'
              : lower.endsWith('.webp')
                  ? 'image/webp'
                  : lower.endsWith('.heic')
                      ? 'image/heic'
                      : 'image/jpeg');
      final doc = await DriverApi.uploadDocument(
        title: 'Rental proof of ownership/insurance — ${vehicle.plateNumber}',
        fileName: picked.name,
        contentType: contentType,
        bytes: bytes,
      );
      if (!mounted) return;
      setState(() {
        _uploadedDocument = doc;
        _uploadingDocument = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _documentError = e is ApiException ? e.message : 'Upload failed. Tap to try again.';
        _uploadingDocument = false;
      });
    }
  }

  Future<void> _submit() async {
    final rate = double.tryParse(_rateController.text.replaceAll(',', '').trim());
    final location = _locationController.text.trim();
    if (_vehicleId == null) {
      setState(() => _formError = 'Add a vehicle first, then list it for rental.');
      return;
    }
    if (rate == null || rate <= 0) {
      setState(() => _formError = 'Enter a valid daily rate');
      return;
    }
    if (location.isEmpty) {
      setState(() => _formError = 'Enter a pickup location');
      return;
    }
    if (_uploadedDocument == null) {
      setState(() => _formError = 'Upload proof of ownership or insurance before submitting.');
      return;
    }
    setState(() {
      _formError = null;
      _submitting = true;
    });
    try {
      await DriverApi.listForRental(
        vehicleId: _vehicleId!,
        dailyRate: rate,
        location: location,
        lat: _pickedLocation?.lat,
        lng: _pickedLocation?.lng,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Listing submitted for admin review.')));
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _formError = e is ApiException ? e.message : 'Could not submit this listing. Please try again.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Luxury Car Rental")),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Partner with RavelGo to rent your car out directly through the app when you're not driving it.",
                style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 20),
              if (_loadingVehicles)
                const Padding(padding: EdgeInsets.all(8), child: Center(child: CircularProgressIndicator()))
              else if (_vehiclesError != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: AppColors.surfaceElevated, borderRadius: BorderRadius.circular(12)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_vehiclesError!, style: const TextStyle(color: AppColors.danger)),
                      TextButton(onPressed: _loadVehicles, child: const Text('Try again')),
                    ],
                  ),
                )
              else if (_vehicles.isEmpty)
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceElevated,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    "You have no vehicles on file yet. Add a vehicle first, then come back to list it for rental.",
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                )
              else
                DropdownButtonFormField<String>(
                  value: _vehicleId,
                  decoration: const InputDecoration(labelText: "Vehicle", border: OutlineInputBorder()),
                  items: _vehicles
                      .map((v) => DropdownMenuItem(
                            value: v.id,
                            child: Text('${v.label.isEmpty ? 'Vehicle' : v.label} · ${v.plateNumber}'),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() {
                    _vehicleId = v;
                    // A previously uploaded document was titled for the old
                    // vehicle's plate — switching vehicles means uploading
                    // again rather than silently attaching the wrong file.
                    _uploadedDocument = null;
                    _documentError = null;
                  }),
                ),
              const SizedBox(height: 16),
              TextField(
                controller: _rateController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(labelText: "Daily rental rate (₦)", border: OutlineInputBorder()),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _locationController,
                readOnly: true,
                onTap: _pickLocation,
                decoration: const InputDecoration(
                  labelText: "Available pickup location",
                  hintText: "Search for a pickup location",
                  suffixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),
              _vehiclePhotoPreview(),
              const SizedBox(height: 10),
              _documentUploadBox(),
              if (_formError != null) ...[
                const SizedBox(height: 12),
                Text(_formError!, style: const TextStyle(color: AppColors.danger)),
              ],
              const SizedBox(height: 24),
              AppComponents.primaryButton(
                text: _submitting ? "Submitting…" : "Submit for review",
                onPressed: _canSubmit ? _submit : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Shows the selected vehicle's own real photo (captured on its vehicle
  /// profile — see AddVehicleScreen) rather than a second, disconnected
  /// upload control here: a rental listing has no photo of its own, only
  /// whichever vehicle it's for.
  Widget _vehiclePhotoPreview() {
    final selected = _selectedVehicle;
    if (selected?.photoUrl != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.network(
          selected!.photoUrl!,
          height: 160,
          width: double.infinity,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
        ),
      );
    }
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: selected == null
          ? null
          : () async {
              final saved = await Navigator.of(context)
                  .push<bool>(MaterialPageRoute(builder: (_) => AddVehicleScreen(existing: selected)));
              if (saved == true) _loadVehicles();
            },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: AppColors.surfaceElevated, borderRadius: BorderRadius.circular(12)),
        child: Row(
          children: [
            const Icon(Icons.add_a_photo_outlined, color: AppColors.textSecondary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                selected == null
                    ? "Pick a vehicle above to show its photo here."
                    : "This vehicle has no photo yet — tap to add one.",
                style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Real upload control for "proof of ownership / insurance": disabled
  /// with an explanatory label until a vehicle is picked, then shows an
  /// uploading spinner, an uploaded confirmation, or an error the driver can
  /// tap to retry — never a decorative box that does nothing.
  Widget _documentUploadBox() {
    final disabled = _selectedVehicle == null || _uploadingDocument;
    IconData icon = Icons.upload_file_outlined;
    Color iconColor = AppColors.textSecondary;
    String label = _selectedVehicle == null
        ? "Pick a vehicle above, then upload proof of ownership / insurance"
        : "Upload proof of ownership / insurance";
    Widget trailing = const Icon(Icons.chevron_right, size: 18, color: AppColors.textMuted);

    if (_uploadingDocument) {
      label = "Uploading…";
      trailing = const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2));
    } else if (_documentError != null) {
      icon = Icons.error_outline;
      iconColor = AppColors.danger;
      label = "${_documentError!} Tap to retry.";
    } else if (_uploadedDocument != null) {
      icon = Icons.check_circle_outline;
      iconColor = AppColors.success;
      label = "Document uploaded — awaiting review. Tap to replace.";
    }

    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.small),
      onTap: disabled ? null : _pickAndUploadDocument,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.small),
          border: Border.all(color: AppColors.border),
          color: AppColors.surface,
        ),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(color: AppColors.surfaceElevated, borderRadius: BorderRadius.circular(AppRadius.small)),
              child: Icon(icon, color: iconColor),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(child: Text(label, style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary))),
            trailing,
          ],
        ),
      ),
    );
  }
}
