import 'package:flutter/material.dart';
import 'package:ravelgo_driver_app/services/api_client.dart';
import 'package:ravelgo_driver_app/services/driver_api.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';

/// Add or edit a vehicle. Real backend-backed: POST /api/vehicles to add,
/// PATCH /api/vehicles/:id to edit. Pops `true` on success so the caller
/// reloads the real list rather than trusting a locally-fabricated record.
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

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      if (_isEditing) {
        await DriverApi.updateVehicle(
          widget.existing!.id,
          brand: _brand.text.trim(),
          model: _model.text.trim(),
          colour: _colour.text.trim(),
          plateNumber: _plate.text.trim(),
          year: _year.text.trim(),
          isPrimary: _isPrimary,
        );
      } else {
        await DriverApi.addVehicle(
          brand: _brand.text.trim(),
          model: _model.text.trim(),
          colour: _colour.text.trim(),
          plateNumber: _plate.text.trim(),
          year: _year.text.trim(),
          isPrimary: _isPrimary,
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
}
