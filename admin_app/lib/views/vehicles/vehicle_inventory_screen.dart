import 'package:flutter/material.dart';
import 'package:ravelgo_admin/services/admin_api.dart';
import 'package:ravelgo_admin/services/api_client.dart';
import 'package:ravelgo_admin/theme/app_theme.dart';

/// Read-only cross-driver vehicle inventory (GET /api/vehicles, admin-only).
/// There's no admin write endpoint for another driver's vehicle — only the
/// owning driver can edit/delete their own — so this is view-only by design.
class VehicleInventoryScreen extends StatefulWidget {
  const VehicleInventoryScreen({super.key});

  @override
  State<VehicleInventoryScreen> createState() => _VehicleInventoryScreenState();
}

class _VehicleInventoryScreenState extends State<VehicleInventoryScreen> {
  bool _loading = true;
  String? _error;
  List<AdminVehicle> _vehicles = const [];

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
      final vehicles = await AdminApi.vehicles();
      if (!mounted) return;
      setState(() {
        _vehicles = vehicles;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException && e.statusCode == 403
            ? 'Sign in as an admin to view the vehicle inventory.'
            : e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Vehicle Inventory")),
      body: _loading ? const Center(child: CircularProgressIndicator()) : (_error != null ? _err() : _list()),
    );
  }

  Widget _err() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.danger)),
            TextButton(onPressed: _load, child: const Text('Try again')),
          ]),
        ),
      );

  Widget _list() {
    if (_vehicles.isEmpty) {
      return const Center(child: Text("No vehicles yet.", style: TextStyle(color: AppColors.textSecondary)));
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
          return Container(
            padding: const EdgeInsets.all(14),
            decoration: AppComponents.cardDecoration(),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("${v.year} ${v.brand} ${v.model}".trim(),
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text("${v.colour} · ${v.plateNumber}",
                          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                      const SizedBox(height: 4),
                      Text(v.ownerName.isEmpty ? v.ownerEmail : v.ownerName,
                          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                    ],
                  ),
                ),
                if (v.listedForRental) AppComponents.badge("Listed for rental", color: AppColors.info),
              ],
            ),
          );
        },
      ),
    );
  }
}
