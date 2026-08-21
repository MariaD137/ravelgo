import 'package:flutter/material.dart';
import 'package:ravelgo_driver_app/services/api_client.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';
import 'package:ravelgo_driver_app/views/auth/verify_account_screen.dart';

class VehicleInformationScreen extends StatefulWidget {
  final String email;
  const VehicleInformationScreen({super.key, required this.email});

  @override
  State<VehicleInformationScreen> createState() => _VehicleInformationScreenState();
}

class _VehicleInformationScreenState extends State<VehicleInformationScreen> {
  final _brandController = TextEditingController();
  final _modelController = TextEditingController();
  final _colourController = TextEditingController();
  final _plateController = TextEditingController();
  final _yearController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _brandController.dispose();
    _modelController.dispose();
    _colourController.dispose();
    _plateController.dispose();
    _yearController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final brand = _brandController.text.trim();
    final model = _modelController.text.trim();
    final colour = _colourController.text.trim();
    final plate = _plateController.text.trim();
    final year = _yearController.text.trim();

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

      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => VerifyAccountScreen(email: widget.email)),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to save vehicle information. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppComponents.header(context, "Vehicle information"),
              const SizedBox(height: 20),
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
              TextField(controller: _brandController, decoration: const InputDecoration(labelText: "Brand", border: OutlineInputBorder())),
              const SizedBox(height: 16),
              TextField(controller: _modelController, decoration: const InputDecoration(labelText: "Model", border: OutlineInputBorder())),
              const SizedBox(height: 16),
              TextField(controller: _colourController, decoration: const InputDecoration(labelText: "Colour", border: OutlineInputBorder())),
              const SizedBox(height: 16),
              TextField(controller: _plateController, decoration: const InputDecoration(labelText: "Plate number", border: OutlineInputBorder())),
              const SizedBox(height: 16),
              TextField(controller: _yearController, decoration: const InputDecoration(labelText: "Year", border: OutlineInputBorder()), keyboardType: TextInputType.number),
              const SizedBox(height: 24),
              AppComponents.uploadBox("Upload vehicle registration (Car Papers)"),
              const SizedBox(height: 12),
              AppComponents.uploadBox("Upload roadworthiness certificate"),
              const SizedBox(height: 12),
              AppComponents.uploadBox("Upload insurance certificate"),
              const SizedBox(height: 28),
              AppComponents.primaryButton(
                text: _isLoading ? "Saving..." : "Continue",
                onPressed: _isLoading ? null : _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
