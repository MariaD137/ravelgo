import 'package:flutter/material.dart';
import 'package:ravelgo_driver_app/models/vehicle.dart';
import 'package:ravelgo_driver_app/services/api/api_client.dart';
import 'package:ravelgo_driver_app/services/driver_session.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';

class AddVehicleScreen extends StatefulWidget {
  const AddVehicleScreen({super.key});

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
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _brand.dispose();
    _model.dispose();
    _colour.dispose();
    _plate.dispose();
    _year.dispose();
    super.dispose();
  }

  String? _required(String? v) => (v == null || v.trim().isEmpty) ? 'Required' : null;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final json = await DriverSession.instance.vehicleApi.create(
        brand: _brand.text.trim(),
        model: _model.text.trim(),
        colour: _colour.text.trim(),
        plateNumber: _plate.text.trim(),
        year: _year.text.trim(),
      );
      if (!mounted) return;
      Navigator.pop(context, Vehicle.fromJson(json));
    } on ApiException catch (err) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = err.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Add Vehicle")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: _brand,
                decoration: const InputDecoration(labelText: "Brand", border: OutlineInputBorder()),
                validator: _required,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _model,
                decoration: const InputDecoration(labelText: "Model", border: OutlineInputBorder()),
                validator: _required,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _colour,
                decoration: const InputDecoration(labelText: "Colour", border: OutlineInputBorder()),
                validator: _required,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _plate,
                decoration: const InputDecoration(labelText: "Plate number", border: OutlineInputBorder()),
                validator: _required,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _year,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: "Year", border: OutlineInputBorder()),
                validator: (v) {
                  final value = v?.trim() ?? '';
                  if (value.isEmpty) return 'Required';
                  if (value.length < 4) return 'Enter a 4-digit year';
                  return null;
                },
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
              ],
              const SizedBox(height: 28),
              AppComponents.primaryButton(text: _submitting ? "Saving…" : "Save vehicle", onPressed: _submitting ? null : _submit),
            ],
          ),
        ),
      ),
    );
  }
}
