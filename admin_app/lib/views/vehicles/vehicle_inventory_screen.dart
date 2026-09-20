import 'package:flutter/material.dart';
import 'package:ravelgo_admin/services/admin_api.dart';
import 'package:ravelgo_admin/services/api_client.dart';
import 'package:ravelgo_admin/theme/app_theme.dart';
import 'package:ravelgo_admin/widgets/pagination_bar.dart';


/// Cross-driver vehicle inventory (GET /api/vehicles, admin-only). Admin
/// cannot edit a driver's own vehicle details (brand/plate/etc — only the
/// owning driver can), but CAN set/correct which ride-category vehicle class
/// (Economy/Comfort/Premium/Luxury) a vehicle counts as, via the real
/// PATCH /api/admin/vehicles/:id/class endpoint — this is what
/// services/matching.ts actually reads when a ride category restricts
/// itself to specific vehicle classes.
class VehicleInventoryScreen extends StatefulWidget {
  const VehicleInventoryScreen({super.key});

  @override
  State<VehicleInventoryScreen> createState() => _VehicleInventoryScreenState();
}

class _VehicleInventoryScreenState extends State<VehicleInventoryScreen> {
  bool _loading = true;
  String? _error;
  int _page = 1;
  int _totalPages = 1;
  int _total = 0;
  List<AdminVehicle> _vehicles = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({int? page}) async {
    if (page != null) _page = page;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await AdminApi.vehicles(page: _page);
      if (!mounted) return;
      if (result.isPastEnd) return await _load(page: result.totalPages);
      setState(() {
        _vehicles = result.items;
        _total = result.total;
        _totalPages = result.totalPages;
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
    return Column(
      children: [
        Expanded(child: _listView()),
        PaginationBar(
          page: _page,
          totalPages: _totalPages,
          total: _total,
          itemLabel: 'vehicles',
          busy: _loading,
          onPageChanged: (p) => _load(page: p),
        ),
      ],
    );
  }

  Widget _listView() {
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
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
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Text("Ride class:", style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButton<String?>(
                        isDense: true,
                        isExpanded: true,
                        value: v.vehicleClass,
                        hint: const Text("Unclassified", style: TextStyle(fontSize: 13)),
                        items: [
                          const DropdownMenuItem<String?>(value: null, child: Text("Unclassified")),
                          ...rideVehicleClasses.map((c) => DropdownMenuItem<String?>(value: c, child: Text(c))),
                        ],
                        onChanged: (value) => _setClass(v, value),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _setClass(AdminVehicle vehicle, String? vehicleClass) async {
    final index = _vehicles.indexOf(vehicle);
    try {
      await AdminApi.setVehicleClass(vehicle.id, vehicleClass);
      if (!mounted) return;
      setState(() {
        _vehicles = [..._vehicles]..[index] = AdminVehicle(
            id: vehicle.id,
            brand: vehicle.brand,
            model: vehicle.model,
            colour: vehicle.colour,
            plateNumber: vehicle.plateNumber,
            year: vehicle.year,
            listedForRental: vehicle.listedForRental,
            ownerName: vehicle.ownerName,
            ownerEmail: vehicle.ownerEmail,
            vehicleClass: vehicleClass,
          );
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is ApiException ? e.message : "Could not update this vehicle's class.")),
      );
    }
  }
}
