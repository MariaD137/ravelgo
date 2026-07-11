import 'package:flutter/material.dart';
import 'package:ravelgo_driver_app/models/vehicle.dart';
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Add Vehicle")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(controller: _brand, decoration: const InputDecoration(labelText: "Brand", border: OutlineInputBorder())),
            const SizedBox(height: 16),
            TextField(controller: _model, decoration: const InputDecoration(labelText: "Model", border: OutlineInputBorder())),
            const SizedBox(height: 16),
            TextField(controller: _colour, decoration: const InputDecoration(labelText: "Colour", border: OutlineInputBorder())),
            const SizedBox(height: 16),
            TextField(controller: _plate, decoration: const InputDecoration(labelText: "Plate number", border: OutlineInputBorder())),
            const SizedBox(height: 16),
            TextField(controller: _year, decoration: const InputDecoration(labelText: "Year", border: OutlineInputBorder())),
            const SizedBox(height: 24),
            AppComponents.uploadBox("Upload vehicle registration (Car Papers)"),
            const SizedBox(height: 28),
            AppComponents.primaryButton(
              text: "Save vehicle",
              onPressed: () {
                Navigator.pop(
                  context,
                  Vehicle(
                    brand: _brand.text.isEmpty ? "Toyota" : _brand.text,
                    model: _model.text.isEmpty ? "Corolla" : _model.text,
                    colour: _colour.text.isEmpty ? "White" : _colour.text,
                    plateNumber: _plate.text.isEmpty ? "NEW-000-XX" : _plate.text,
                    year: _year.text.isEmpty ? "2022" : _year.text,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
