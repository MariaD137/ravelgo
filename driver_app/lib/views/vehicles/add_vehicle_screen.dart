import 'package:flutter/material.dart';
import 'package:ravelgo_driver_app/models/vehicle.dart';
import 'package:ravelgo_driver_app/services/api_client.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';

class AddVehicleScreen extends StatefulWidget {
  const AddVehicleScreen({super.key});

  @override
  State<AddVehicleScreen> createState() => _AddVehicleScreenState();
}

class _AddVehicleScreenState extends State<AddVehicleScreen> {
  final _brand = TextEditingController();
  final _model = TextEditingController();
  final _colour = TextEditingController();
  final _plate = TextEditingController();
  final _year = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _brand.dispose();
    _model.dispose();
    _colour.dispose();
    _plate.dispose();
    _year.dispose();
    super.dispose();
  }

  Future<void> _saveVehicle() async {
    final brand = _brand.text.trim();
    final model = _model.text.trim();
    final colour = _colour.text.trim();
    final plate = _plate.text.trim();
    final year = _year.text.trim();

    if (brand.isEmpty || model.isEmpty || colour.isEmpty || plate.isEmpty || year.isEmpty) {
      setState(() => _errorMessage = 'Please fill in all fields');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await ApiClient().post('/vehicles', body: {
        'brand': brand,
        'model': model,
        'colour': colour,
        'plateNumber': plate,
        'year': year,
      });

      if (!mounted) return;

      Navigator.pop(
        context,
        Vehicle(
          brand: brand,
          model: model,
          colour: colour,
          plateNumber: plate,
          year: year,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to save vehicle. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Add Vehicle")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_errorMessage != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red[200]!),
                ),
                child: Text(
                  _errorMessage!,
                  style: TextStyle(color: Colors.red[800], fontSize: 14),
                ),
              ),
              const SizedBox(height: 16),
            ],
            TextField(controller: _brand, decoration: const InputDecoration(labelText: "Brand", border: OutlineInputBorder())),
            const SizedBox(height: 16),
            TextField(controller: _model, decoration: const InputDecoration(labelText: "Model", border: OutlineInputBorder())),
            const SizedBox(height: 16),
            TextField(controller: _colour, decoration: const InputDecoration(labelText: "Colour", border: OutlineInputBorder())),
            const SizedBox(height: 16),
            TextField(controller: _plate, decoration: const InputDecoration(labelText: "Plate number", border: OutlineInputBorder())),
            const SizedBox(height: 16),
            TextField(controller: _year, decoration: const InputDecoration(labelText: "Year", border: OutlineInputBorder()), keyboardType: TextInputType.number),
            const SizedBox(height: 24),
            AppComponents.uploadBox("Upload vehicle registration (Car Papers)"),
            const SizedBox(height: 28),
            _isLoading
                ? const Center(child: CircularProgressIndicator())
                : AppComponents.primaryButton(
                    text: "Save vehicle",
                    onPressed: _saveVehicle,
                  ),
          ],
        ),
      ),
    );
  }
}
