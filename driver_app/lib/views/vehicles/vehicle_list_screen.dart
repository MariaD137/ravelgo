import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:ravelgo_driver_app/models/vehicle.dart';
import 'package:ravelgo_driver_app/services/auth_session.dart';
import 'package:ravelgo_driver_app/services/driver_api.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';
import 'package:ravelgo_driver_app/views/vehicles/add_vehicle_screen.dart';
import 'package:ravelgo_driver_app/views/vehicles/vehicle_detail_screen.dart';

enum _LoadState { loading, loaded, error }

class VehicleListScreen extends StatefulWidget {
  // Injectable for tests; production call sites (Account tab, side drawer)
  // omit this and get the real dotenv-configured client.
  final DriverApi? api;
  const VehicleListScreen({super.key, this.api});

  @override
  State<VehicleListScreen> createState() => _VehicleListScreenState();
}

class _VehicleListScreenState extends State<VehicleListScreen> {
  late final DriverApi _api = widget.api ??
      DriverApi(baseUrl: dotenv.env['API_BASE_URL'] ?? '', authTokenProvider: const CognitoAuthTokenProvider());

  _LoadState _state = _LoadState.loading;
  List<Vehicle> _vehicles = [];
  String _errorMessage = "Unable to load your vehicles";

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _state = _LoadState.loading);
    try {
      final vehicles = await _api.fetchVehicles();
      if (!mounted) return;
      setState(() {
        _vehicles = vehicles;
        _state = _LoadState.loaded;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e is DriverApiException ? e.message : "Please check your connection and try again.";
        _state = _LoadState.error;
      });
    }
  }

  Future<void> _openAddVehicle() async {
    final added = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => AddVehicleScreen(api: _api)));
    if (added == true) _load();
  }

  Future<void> _openDetail(Vehicle vehicle) async {
    // Always reload on return, regardless of how the detail screen was
    // exited (back button, edit, deactivate, photo/document changes) —
    // simpler and more robust than threading a "did anything change" flag
    // back through every possible exit path.
    await Navigator.push(context, MaterialPageRoute(builder: (_) => VehicleDetailScreen(vehicleId: vehicle.id, api: _api)));
    _load();
  }

  (Color, String) _verificationBadge(VehicleVerificationStatus status) {
    switch (status) {
      case VehicleVerificationStatus.approved:
        return (AppColors.success, "Approved");
      case VehicleVerificationStatus.pending:
        return (Colors.orange, "Pending review");
      case VehicleVerificationStatus.rejected:
        return (AppColors.danger, "Rejected");
      case VehicleVerificationStatus.resubmissionRequired:
        return (Colors.orange, "Needs resubmission");
    }
  }

  Widget _buildBody() {
    switch (_state) {
      case _LoadState.loading:
        return const Center(child: Padding(padding: EdgeInsets.only(top: 60), child: Column(
          children: [CircularProgressIndicator(), SizedBox(height: 12), Text("Loading your vehicles...", style: TextStyle(color: Colors.black54))],
        )));
      case _LoadState.error:
        const errorTitle = "Unable to load your vehicles";
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const SizedBox(height: 40),
              const Text(errorTitle, style: TextStyle(fontWeight: FontWeight.w600)),
              // Only shown when the backend/network gave a more specific
              // reason than the generic title above.
              if (_errorMessage != errorTitle) ...[
                const SizedBox(height: 6),
                Text(_errorMessage, style: const TextStyle(fontSize: 12.5, color: Colors.black54), textAlign: TextAlign.center),
              ],
              const SizedBox(height: 16),
              AppComponents.outlineButton(text: "Try again", onPressed: _load),
            ],
          ),
        );
      case _LoadState.loaded:
        if (_vehicles.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                const SizedBox(height: 60),
                const Icon(Icons.directions_car_outlined, size: 48, color: Colors.black26),
                const SizedBox(height: 12),
                const Text("No vehicles yet", style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                const Text(
                  "Add a vehicle to start receiving ride, courier, and rental requests.",
                  style: TextStyle(fontSize: 12.5, color: Colors.black54),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: _load,
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: _vehicles.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final v = _vehicles[i];
              final (badgeColor, badgeLabel) = _verificationBadge(v.verificationStatus);
              final photoUrl = v.primaryPhoto?.url;
              return InkWell(
                onTap: () => _openDetail(v),
                borderRadius: BorderRadius.circular(12),
                child: Opacity(
                  opacity: v.isActive ? 1.0 : 0.5,
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: AppComponents.cardDecoration(),
                    child: Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          clipBehavior: Clip.antiAlias,
                          decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(10)),
                          child: photoUrl != null
                              ? Image.network(photoUrl, fit: BoxFit.cover, errorBuilder: (_, _, _) => const Icon(Icons.directions_car, color: Colors.black54))
                              : const Icon(Icons.directions_car, color: Colors.black54),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("${v.brand} ${v.model} · ${v.colour}", style: const TextStyle(fontWeight: FontWeight.w600)),
                              const SizedBox(height: 4),
                              Text(
                                "${v.plateNumber} · ${v.year}${v.isActive ? '' : ' · Deactivated'}",
                                style: const TextStyle(fontSize: 12, color: Colors.black54),
                              ),
                              const SizedBox(height: 6),
                              Wrap(spacing: 6, runSpacing: 4, children: [
                                AppComponents.badge(badgeLabel, color: badgeColor),
                                if (v.isPrimary) AppComponents.badge("Primary"),
                                if (v.listedForRental) AppComponents.badge("For rental", color: Colors.blue),
                              ]),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right, color: Colors.black26),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("My Vehicles")),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.black,
        onPressed: _openAddVehicle,
        child: const Icon(Icons.add),
      ),
      body: _buildBody(),
    );
  }
}
