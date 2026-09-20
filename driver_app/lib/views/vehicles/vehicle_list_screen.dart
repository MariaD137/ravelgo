import 'package:flutter/material.dart';
import 'package:ravelgo_driver_app/services/api_client.dart';
import 'package:ravelgo_driver_app/services/driver_api.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';
import 'package:ravelgo_driver_app/views/vehicles/add_vehicle_screen.dart';

/// The driver's real vehicles — the single source of truth also used by the
/// rental-listing flow (DriverApi.myVehicles()). No local/hardcoded records.
class VehicleListScreen extends StatefulWidget {
  const VehicleListScreen({super.key});

  @override
  State<VehicleListScreen> createState() => _VehicleListScreenState();
}

class _VehicleListScreenState extends State<VehicleListScreen> {
  bool _loading = true;
  bool _busy = false;
  String? _error;
  List<Vehicle> _vehicles = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final vehicles = await DriverApi.myVehicles();
      if (!mounted) return;
      setState(() {
        _vehicles = vehicles;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = describeApiFailure(e, what: 'your vehicles');
        _loading = false;
      });
    }
  }

  Future<void> _addOrEdit({Vehicle? existing}) async {
    final saved = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => AddVehicleScreen(existing: existing)));
    if (saved == true) _load();
  }

  Future<void> _delete(Vehicle v) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove vehicle'),
        content: Text('Remove ${v.label.isEmpty ? 'this vehicle' : v.label} (${v.plateNumber})?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remove')),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      await DriverApi.deleteVehicle(v.id);
      await _load();
    } catch (e) {
      if (!mounted) return;
      final message = e is ApiException ? e.message : 'Could not remove this vehicle.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("My Vehicles")),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        onPressed: (_busy || _loading || _error != null) ? null : () => _addOrEdit(),
        child: const Icon(Icons.add),
      ),
      body: _body(),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.danger)),
              TextButton(onPressed: _load, child: const Text('Try again')),
            ],
          ),
        ),
      );
    }
    if (_vehicles.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text("You haven't added a vehicle yet. Tap + to add one.", style: TextStyle(color: AppColors.textSecondary)),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _vehicles.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          final v = _vehicles[i];
          return InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: _busy ? null : () => _addOrEdit(existing: v),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: AppComponents.cardDecoration(),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(10)),
                    clipBehavior: Clip.antiAlias,
                    child: v.photoUrl != null
                        ? Image.network(
                            v.photoUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Icon(Icons.directions_car, color: AppColors.textSecondary),
                          )
                        : const Icon(Icons.directions_car, color: AppColors.textSecondary),
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
                  if (v.listedForRental) AppComponents.badge("For rental", color: AppColors.info),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: AppColors.danger),
                    onPressed: _busy ? null : () => _delete(v),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
