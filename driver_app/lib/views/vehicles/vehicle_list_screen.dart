import 'package:flutter/material.dart';
import 'package:ravelgo_driver_app/models/vehicle.dart';
import 'package:ravelgo_driver_app/services/api/api_client.dart';
import 'package:ravelgo_driver_app/services/driver_session.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';
import 'package:ravelgo_driver_app/views/vehicles/add_vehicle_screen.dart';

class VehicleListScreen extends StatefulWidget {
  const VehicleListScreen({super.key});

  @override
  State<VehicleListScreen> createState() => _VehicleListScreenState();
}

class _VehicleListScreenState extends State<VehicleListScreen> {
  late Future<List<Vehicle>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Vehicle>> _load() async {
    final raw = await DriverSession.instance.vehicleApi.listMine();
    return raw.map(Vehicle.fromJson).toList();
  }

  void _retry() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("My Vehicles")),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.black,
        onPressed: () async {
          final v = await Navigator.push<Vehicle>(context, MaterialPageRoute(builder: (_) => const AddVehicleScreen()));
          if (v != null) _retry();
        },
        child: const Icon(Icons.add),
      ),
      body: FutureBuilder<List<Vehicle>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            final message = snapshot.error is ApiException ? (snapshot.error as ApiException).message : 'Could not load your vehicles.';
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Colors.black54)),
                    const SizedBox(height: 12),
                    OutlinedButton(onPressed: _retry, child: const Text("Retry")),
                  ],
                ),
              ),
            );
          }
          final vehicles = snapshot.data ?? const [];
          if (vehicles.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text("No vehicles yet — tap + to add one.", style: TextStyle(color: Colors.black54)),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async {
              _retry();
              await _future;
            },
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: vehicles.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final v = vehicles[i];
                final resolvedImageUrl = DriverSession.instance.apiClient.resolveAssetUrl(v.imageUrl);
                return Container(
                  padding: const EdgeInsets.all(14),
                  decoration: AppComponents.cardDecoration(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: AspectRatio(
                          aspectRatio: 16 / 9,
                          child: resolvedImageUrl != null
                              ? Image.network(
                                  resolvedImageUrl,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) => _NoVehiclePhoto(),
                                )
                              : _NoVehiclePhoto(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
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
                    ],
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

/// A clean, honest placeholder shown in place of a real photo — never a
/// stand-in image that could be mistaken for the actual vehicle.
class _NoVehiclePhoto extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.background,
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.directions_car, color: Colors.black38, size: 32),
          const SizedBox(height: 4),
          Text("No vehicle photo", style: TextStyle(color: Colors.black.withValues(alpha: 0.4), fontSize: 12)),
        ],
      ),
    );
  }
}
