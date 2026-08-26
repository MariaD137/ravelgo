import 'package:flutter/material.dart';
import 'package:ravelgo_driver_app/models/vehicle.dart';
import 'package:ravelgo_driver_app/services/driver_api.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';

class AddVehicleScreen extends StatefulWidget {
  final DriverApi api;
  // When reached from "My Vehicles", this screen pops back to the list on
  // success (default). During onboarding it's a forward step instead — the
  // caller passes onSaved to continue to the next onboarding screen rather
  // than popping to a screen that doesn't exist in that stack.
  final VoidCallback? onSaved;
  const AddVehicleScreen({super.key, required this.api, this.onSaved});

  @override
  State<AddVehicleScreen> createState() => _AddVehicleScreenState();
}

class _AddVehicleScreenState extends State<AddVehicleScreen> {
  final _formKey = GlobalKey<FormState>();
  final _brand = TextEditingController();
  final _model = TextEditingController();
  final _colour = TextEditingController();
  final _plate = TextEditingController();
  final _year = TextEditingController();
  final _vin = TextEditingController();
  VehicleType _vehicleType = VehicleType.sedan;

  bool _submitting = false;
  String? _submitError;

  @override
  void dispose() {
    _brand.dispose();
    _model.dispose();
    _colour.dispose();
    _plate.dispose();
    _year.dispose();
    _vin.dispose();
    super.dispose();
  }

  String? _requiredValidator(String? value, {int minLength = 1}) {
    if (value == null || value.trim().length < minLength) {
      return "Required";
    }
    return null;
  }

  String? _yearValidator(String? value) {
    if (value == null || value.trim().isEmpty) return "Required";
    final year = int.tryParse(value.trim());
    if (year == null || value.trim().length != 4) return "Enter a 4-digit year";
    final currentYear = DateTime.now().year;
    if (year < 1980 || year > currentYear + 1) return "Enter a realistic year";
    return null;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _submitting = true;
      _submitError = null;
    });
    try {
      await widget.api.createVehicle(
        brand: _brand.text.trim(),
        model: _model.text.trim(),
        colour: _colour.text.trim(),
        plateNumber: _plate.text.trim(),
        year: _year.text.trim(),
        vin: _vin.text.trim().isEmpty ? null : _vin.text.trim(),
        vehicleType: _vehicleType,
      );
      if (!mounted) return;
      if (widget.onSaved != null) {
        widget.onSaved!();
      } else {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitError = e is DriverApiException ? e.message : "Unable to save this vehicle";
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Add Vehicle")),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: _brand,
                decoration: const InputDecoration(labelText: "Make *", hintText: "e.g. Toyota", border: OutlineInputBorder()),
                validator: _requiredValidator,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _model,
                decoration: const InputDecoration(labelText: "Model *", hintText: "e.g. Camry", border: OutlineInputBorder()),
                validator: _requiredValidator,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _colour,
                decoration: const InputDecoration(labelText: "Colour *", border: OutlineInputBorder()),
                validator: _requiredValidator,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _plate,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(labelText: "Plate number *", border: OutlineInputBorder()),
                validator: _requiredValidator,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _year,
                keyboardType: TextInputType.number,
                maxLength: 4,
                decoration: const InputDecoration(labelText: "Year *", border: OutlineInputBorder(), counterText: ""),
                validator: _yearValidator,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _vin,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: "VIN (optional)",
                  hintText: "17-character vehicle identification number",
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) return null;
                  if (value.trim().length < 5) return "VIN looks too short";
                  return null;
                },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<VehicleType>(
                initialValue: _vehicleType,
                decoration: const InputDecoration(labelText: "Vehicle type *", border: OutlineInputBorder()),
                items: VehicleType.values
                    .map((type) => DropdownMenuItem(value: type, child: Text(vehicleTypeLabel(type))))
                    .toList(),
                onChanged: (value) {
                  if (value != null) setState(() => _vehicleType = value);
                },
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.04), borderRadius: BorderRadius.circular(10)),
                child: const Text(
                  "You'll be able to add photos and required documents (registration, insurance, inspection) from the vehicle's page after saving it. Your vehicle enters PENDING verification as soon as you save it.",
                  style: TextStyle(fontSize: 12.5, color: Colors.black54),
                ),
              ),
              if (_submitError != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: AppColors.danger.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                  child: Text(_submitError!, style: const TextStyle(color: AppColors.danger, fontSize: 13)),
                ),
              ],
              const SizedBox(height: 28),
              _submitting
                  ? const Center(child: CircularProgressIndicator())
                  : AppComponents.primaryButton(text: "Save vehicle", onPressed: _submit),
            ],
          ),
        ),
      ),
    );
  }
}
