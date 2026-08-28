import 'package:flutter/material.dart';
import 'package:ravelgo_driver_app/models/vehicle.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';
import 'package:ravelgo_driver_app/views/vehicles/add_vehicle_screen.dart';

class VehicleListScreen extends StatefulWidget {
  const VehicleListScreen({super.key});

  @override
  State<VehicleListScreen> createState() => _VehicleListScreenState();
}

class _VehicleListScreenState extends State<VehicleListScreen> {
  final List<Vehicle> _vehicles = [
    const Vehicle(brand: "Toyota", model: "Camry", colour: "Black", plateNumber: "LND-482-KJ", year: "2021", isPrimary: true),
    const Vehicle(brand: "Honda", model: "Accord", colour: "Silver", plateNumber: "ABJ-119-XY", year: "2019"),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("My Vehicles")),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.textPrimary,
        onPressed: () async {
          final v = await Navigator.push<Vehicle>(context, MaterialPageRoute(builder: (_) => const AddVehicleScreen()));
          if (v != null) setState(() => _vehicles.add(v));
        },
        child: const Icon(Icons.add),
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _vehicles.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          final v = _vehicles[i];
          return Container(
            padding: const EdgeInsets.all(14),
            decoration: AppComponents.cardDecoration(),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.directions_car, color: AppColors.textSecondary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("${v.brand} ${v.model} · ${v.colour}", style: const TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text("${v.plateNumber} · ${v.year}", style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                    ],
                  ),
                ),
                if (v.isPrimary) AppComponents.badge("Primary"),
                if (v.listedForRental) AppComponents.badge("For rental", color: Colors.blue),
              ],
            ),
          );
        },
      ),
    );
  }
}
