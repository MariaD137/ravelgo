import 'package:flutter/material.dart';
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
            : e.toString();
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
      setState(() => _formError = e is ApiException ? e.message : e.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Luxury Car Rental")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
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
              Text(_vehiclesError!, style: const TextStyle(color: AppColors.danger))
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
                onChanged: (v) => setState(() => _vehicleId = v),
              ),
            const SizedBox(height: 16),
            TextField(
              controller: _rateController,
              keyboardType: TextInputType.number,
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
            AppComponents.uploadBox("Upload proof of ownership / insurance"),
            if (_formError != null) ...[
              const SizedBox(height: 12),
              Text(_formError!, style: const TextStyle(color: AppColors.danger)),
            ],
            const SizedBox(height: 24),
            AppComponents.primaryButton(
              text: _submitting ? "Submitting…" : "Submit for review",
              onPressed: (_submitting || _vehicles.isEmpty) ? null : _submit,
            ),
          ],
        ),
      ),
    );
  }

  /// Shows the selected vehicle's own real photo (captured on its vehicle
  /// profile — see AddVehicleScreen) rather than a second, disconnected
  /// upload control here: a rental listing has no photo of its own, only
  /// whichever vehicle it's for.
  Widget _vehiclePhotoPreview() {
    Vehicle? selected;
    for (final v in _vehicles) {
      if (v.id == _vehicleId) {
        selected = v;
        break;
      }
    }
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
}
