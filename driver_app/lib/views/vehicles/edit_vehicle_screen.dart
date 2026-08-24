import 'package:flutter/material.dart';
import 'package:ravelgo_driver_app/models/vehicle.dart';
import 'package:ravelgo_driver_app/services/driver_api.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';

class EditVehicleScreen extends StatefulWidget {
  final Vehicle vehicle;
  final DriverApi api;
  const EditVehicleScreen({super.key, required this.vehicle, required this.api});

  @override
  State<EditVehicleScreen> createState() => _EditVehicleScreenState();
}

class _EditVehicleScreenState extends State<EditVehicleScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _brand;
  late final TextEditingController _model;
  late final TextEditingController _colour;
  late final TextEditingController _plate;
  late final TextEditingController _year;
  late final TextEditingController _vin;
  late VehicleType _vehicleType;

  bool _submitting = false;
  String? _submitError;

  @override
  void initState() {
    super.initState();
    _brand = TextEditingController(text: widget.vehicle.brand);
    _model = TextEditingController(text: widget.vehicle.model);
    _colour = TextEditingController(text: widget.vehicle.colour);
    _plate = TextEditingController(text: widget.vehicle.plateNumber);
    _year = TextEditingController(text: widget.vehicle.year);
    _vin = TextEditingController(text: widget.vehicle.vin ?? "");
    _vehicleType = widget.vehicle.vehicleType;
  }

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

  String? _requiredValidator(String? value) => (value == null || value.trim().isEmpty) ? "Required" : null;

  String? _yearValidator(String? value) {
    if (value == null || value.trim().isEmpty) return "Required";
    final year = int.tryParse(value.trim());
    if (year == null || value.trim().length != 4) return "Enter a 4-digit year";
    return null;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _submitting = true;
      _submitError = null;
    });
    try {
      await widget.api.updateVehicle(
        widget.vehicle.id,
        brand: _brand.text.trim(),
        model: _model.text.trim(),
        colour: _colour.text.trim(),
        plateNumber: _plate.text.trim(),
        year: _year.text.trim(),
        vin: _vin.text.trim().isEmpty ? null : _vin.text.trim(),
        vehicleType: _vehicleType,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        // The backend 404s a PATCH to a vehicle that no longer belongs to
        // (or exists for) this driver — surfaced as-is rather than a
        // generic error, since it means the driver's local copy is stale.
        _submitError = e is DriverApiException ? e.message : "Unable to save your changes";
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Edit Vehicle")),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: _brand,
                decoration: const InputDecoration(labelText: "Make *", border: OutlineInputBorder()),
                validator: _requiredValidator,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _model,
                decoration: const InputDecoration(labelText: "Model *", border: OutlineInputBorder()),
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
                decoration: const InputDecoration(labelText: "VIN (optional)", border: OutlineInputBorder()),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<VehicleType>(
                value: _vehicleType,
                decoration: const InputDecoration(labelText: "Vehicle type *", border: OutlineInputBorder()),
                items: VehicleType.values
                    .map((type) => DropdownMenuItem(value: type, child: Text(vehicleTypeLabel(type))))
                    .toList(),
                onChanged: (value) {
                  if (value != null) setState(() => _vehicleType = value);
                },
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
                  : AppComponents.primaryButton(text: "Save changes", onPressed: _submit),
            ],
          ),
        ),
      ),
    );
  }
}
