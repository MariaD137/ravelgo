import 'package:flutter/material.dart';
import 'package:ravelgo_driver_app/models/vehicle.dart';
import 'package:ravelgo_driver_app/services/api_client.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';
import 'package:ravelgo_driver_app/views/vehicles/add_vehicle_screen.dart';

class VehicleListScreen extends StatefulWidget {
  const VehicleListScreen({super.key});

  @override
  State<VehicleListScreen> createState() => _VehicleListScreenState();
}

class _VehicleListScreenState extends State<VehicleListScreen> {
  bool _loading = true;
  String? _error;
  List<Vehicle> _vehicles = [];

  @override
  void initState() {
    super.initState();
    _loadVehicles();
  }

  Vehicle _vehicleFromJson(Map<String, dynamic> json) {
    return Vehicle(
      brand: json['brand']?.toString() ?? '',
      model: json['model']?.toString() ?? '',
      colour: json['colour']?.toString() ?? '',
      plateNumber: json['plateNumber']?.toString() ?? '',
      year: json['year']?.toString() ?? '',
      isPrimary: json['isPrimary'] == true,
      listedForRental: json['listedForRental'] == true,
    );
  }

  Future<void> _loadVehicles() async {
    try {
      final response = await ApiClient().get('/vehicles/me');
      if (!mounted) return;
      final List<dynamic> vehicleList = response is List ? response : [];
      setState(() {
        _vehicles = vehicleList.map((v) => _vehicleFromJson(Map<String, dynamic>.from(v))).toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("My Vehicles")),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.black,
        onPressed: () async {
          final v = await Navigator.push<Vehicle>(context, MaterialPageRoute(builder: (_) => const AddVehicleScreen()));
          if (v != null) {
            // Reload from API after adding a vehicle
            setState(() { _loading = true; _error = null; });
            _loadVehicles();
          }
        },
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Failed to load vehicles', style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        Text(_error!, style: const TextStyle(fontSize: 12, color: Colors.black54), textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        AppComponents.outlineButton(text: "Retry", onPressed: () { setState(() { _loading = true; _error = null; }); _loadVehicles(); }),
                      ],
                    ),
                  ),
                )
              : _vehicles.isEmpty
                  ? const Center(child: Text("No vehicles added yet", style: TextStyle(color: Colors.black54)))
                  : ListView.separated(
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
                                child: const Icon(Icons.directions_car, color: Colors.black54),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text("${v.brand} ${v.model} · ${v.colour}", style: const TextStyle(fontWeight: FontWeight.w600)),
                                    const SizedBox(height: 4),
                                    Text("${v.plateNumber} · ${v.year}", style: const TextStyle(fontSize: 12, color: Colors.black54)),
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
