import 'package:flutter/material.dart';
import 'package:ravelgo_admin/services/admin_api.dart';
import 'package:ravelgo_admin/services/api_client.dart';
import 'package:ravelgo_admin/theme/app_theme.dart';
import 'package:ravelgo_admin/widgets/admin_search_field.dart';
import 'package:ravelgo_admin/widgets/pagination_bar.dart';
import 'package:ravelgo_admin/widgets/reject_reason_dialog.dart';

/// Cross-driver vehicle inventory (GET /api/vehicles, admin-only). Admin
/// cannot edit a driver's own vehicle details (brand/plate/etc — only the
/// owning driver can), but CAN set/correct which ride-category vehicle class
/// (Economy/Comfort/Premium/Luxury) a vehicle counts as, via the real
/// PATCH /api/admin/vehicles/:id/class endpoint — this is what
/// services/matching.ts actually reads when a ride category restricts
/// itself to specific vehicle classes. Separately, admin can approve/reject
/// the vehicle itself (PATCH /api/admin/vehicles/:id/approval) — a safety/
/// eligibility review independent of both the driver's own approval and the
/// ride-class assignment above.
class VehicleInventoryScreen extends StatefulWidget {
  const VehicleInventoryScreen({super.key});

  @override
  State<VehicleInventoryScreen> createState() => _VehicleInventoryScreenState();
}

class _VehicleInventoryScreenState extends State<VehicleInventoryScreen> {
  bool _loading = true;
  bool _busy = false;
  String? _error;
  int _page = 1;
  int _totalPages = 1;
  int _total = 0;
  String? _q;
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
      final result = await AdminApi.vehicles(page: _page, q: _q);
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

  // A search narrowing the whole table must reset to page 1 — otherwise an
  // admin paged to, say, page 4 would see "no results" for a search that
  // actually matches plenty, just not on that now-stale page.
  void _onSearchChanged(String? q) {
    _q = q;
    _load(page: 1);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Vehicle Inventory")),
      body: Column(
        children: [
          AdminSearchField(hintText: 'Search plate, make, model or owner…', onChanged: _onSearchChanged),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : (_error != null ? _err() : _list()),
          ),
        ],
      ),
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

  Color _approvalColor(String s) => switch (s) {
        'APPROVED' => AppColors.success,
        'REJECTED' => AppColors.danger,
        _ => AppColors.warning,
      };

  String _label(String s) => s.isEmpty ? '' : s[0] + s.substring(1).toLowerCase().replaceAll('_', ' ');

  Widget _listView() {
    if (_vehicles.isEmpty) {
      return Center(
        child: Text(
          _q == null ? "No vehicles yet." : "No vehicles match \"$_q\".",
          style: const TextStyle(color: AppColors.textSecondary),
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
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        AppComponents.badge(_label(v.approvalStatus), color: _approvalColor(v.approvalStatus)),
                        if (v.listedForRental) ...[
                          const SizedBox(height: 4),
                          AppComponents.badge("Listed for rental", color: AppColors.info),
                        ],
                      ],
                    ),
                  ],
                ),
                if (v.approvalStatus == 'REJECTED' && (v.rejectionReason?.isNotEmpty ?? false))
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text('Reason: ${v.rejectionReason}',
                        style: const TextStyle(fontSize: 12, color: AppColors.danger)),
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
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (v.approvalStatus != 'APPROVED')
                      Expanded(
                        child: AppComponents.outlineButton(
                          text: 'Approve',
                          color: AppColors.success,
                          onPressed: _busy ? null : () => _approve(v),
                        ),
                      ),
                    if (v.approvalStatus != 'APPROVED' && v.approvalStatus != 'REJECTED')
                      const SizedBox(width: 8),
                    if (v.approvalStatus != 'REJECTED')
                      Expanded(
                        child: AppComponents.outlineButton(
                          text: 'Reject',
                          color: AppColors.danger,
                          onPressed: _busy ? null : () => _reject(v),
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

  void _replace(AdminVehicle vehicle, AdminVehicle updated) {
    final index = _vehicles.indexOf(vehicle);
    if (index == -1) return;
    setState(() => _vehicles = [..._vehicles]..[index] = updated);
  }

  Future<void> _approve(AdminVehicle vehicle) async {
    setState(() => _busy = true);
    try {
      await AdminApi.setVehicleApproval(vehicle.id, 'APPROVED');
      if (!mounted) return;
      _replace(
        vehicle,
        AdminVehicle(
          id: vehicle.id,
          brand: vehicle.brand,
          model: vehicle.model,
          colour: vehicle.colour,
          plateNumber: vehicle.plateNumber,
          year: vehicle.year,
          listedForRental: vehicle.listedForRental,
          ownerName: vehicle.ownerName,
          ownerEmail: vehicle.ownerEmail,
          vehicleClass: vehicle.vehicleClass,
          approvalStatus: 'APPROVED',
          rejectionReason: null,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is ApiException ? e.message : "Could not approve this vehicle.")),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reject(AdminVehicle vehicle) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => RejectReasonDialog(itemLabel: '${vehicle.brand} ${vehicle.model} (${vehicle.plateNumber})'),
    );
    if (reason == null) return; // cancelled
    setState(() => _busy = true);
    try {
      await AdminApi.setVehicleApproval(vehicle.id, 'REJECTED', rejectionReason: reason);
      if (!mounted) return;
      _replace(
        vehicle,
        AdminVehicle(
          id: vehicle.id,
          brand: vehicle.brand,
          model: vehicle.model,
          colour: vehicle.colour,
          plateNumber: vehicle.plateNumber,
          year: vehicle.year,
          listedForRental: vehicle.listedForRental,
          ownerName: vehicle.ownerName,
          ownerEmail: vehicle.ownerEmail,
          vehicleClass: vehicle.vehicleClass,
          approvalStatus: 'REJECTED',
          rejectionReason: reason,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is ApiException ? e.message : "Could not reject this vehicle.")),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setClass(AdminVehicle vehicle, String? vehicleClass) async {
    try {
      await AdminApi.setVehicleClass(vehicle.id, vehicleClass);
      if (!mounted) return;
      _replace(
        vehicle,
        AdminVehicle(
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
          approvalStatus: vehicle.approvalStatus,
          rejectionReason: vehicle.rejectionReason,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is ApiException ? e.message : "Could not update this vehicle's class.")),
      );
    }
  }
}
