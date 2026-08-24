import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:ravelgo_admin/services/admin_api.dart';
import 'package:ravelgo_admin/services/auth_session.dart';
import 'package:ravelgo_admin/theme/app_theme.dart';
import 'package:ravelgo_admin/views/drivers/driver_detail_screen.dart';

enum _LoadState { loading, loaded, error }

class DriverListScreen extends StatefulWidget {
  final bool embedded;
  // Injectable for tests; production call sites (AdminShell) omit this and
  // get the real dotenv-configured client.
  final AdminApi? api;
  const DriverListScreen({super.key, this.embedded = false, this.api});

  @override
  State<DriverListScreen> createState() => _DriverListScreenState();
}

class _DriverListScreenState extends State<DriverListScreen> {
  late final AdminApi _api = widget.api ??
      AdminApi(baseUrl: dotenv.env['API_BASE_URL'] ?? '', authTokenProvider: const CognitoAuthTokenProvider());

  _LoadState _state = _LoadState.loading;
  List<AdminDriverSummary> _drivers = [];
  String _errorMessage = "Unable to load drivers";

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _state = _LoadState.loading);
    try {
      final paged = await _api.fetchDrivers(pageSize: 100);
      if (!mounted) return;
      setState(() {
        _drivers = paged.drivers;
        _state = _LoadState.loaded;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e is AdminApiException ? e.message : "Unable to load drivers";
        _state = _LoadState.error;
      });
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case "ACTIVE":
        return AppColors.success;
      case "SUSPENDED":
        return AppColors.danger;
      default:
        return AppColors.warning;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case "ACTIVE":
        return "Active";
      case "SUSPENDED":
        return "Suspended";
      default:
        return "Pending review";
    }
  }

  Widget _buildBody() {
    switch (_state) {
      case _LoadState.loading:
        return const Center(child: CircularProgressIndicator());
      case _LoadState.error:
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text("Unable to load drivers", style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Text(_errorMessage, style: const TextStyle(fontSize: 12.5, color: Colors.black54), textAlign: TextAlign.center),
              const SizedBox(height: 16),
              AppComponents.outlineButton(text: "Try again", onPressed: _load),
            ],
          ),
        );
      case _LoadState.loaded:
        if (_drivers.isEmpty) {
          return const Center(child: Text("No drivers yet", style: TextStyle(color: Colors.black54)));
        }
        return RefreshIndicator(
          onRefresh: _load,
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: _drivers.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final d = _drivers[i];
              final vehicleLabel = d.vehicles.isEmpty ? "No vehicle on file" : "${d.vehicles.first.brand} ${d.vehicles.first.model}";
              return InkWell(
                onTap: () async {
                  await Navigator.push(context, MaterialPageRoute(builder: (_) => DriverDetailScreen(driverId: d.id, api: _api)));
                  _load();
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: AppComponents.cardDecoration(),
                  child: Row(
                    children: [
                      const CircleAvatar(radius: 22, backgroundColor: Color(0xFFF0F0F0), child: Icon(Icons.person, color: Colors.black45)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(d.name.isEmpty ? d.email : d.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                            const SizedBox(height: 4),
                            Text("$vehicleLabel · ${d.totalTrips} trips · ★ ${d.rating.toStringAsFixed(1)}", style: const TextStyle(fontSize: 12, color: Colors.black54)),
                          ],
                        ),
                      ),
                      AppComponents.badge(_statusLabel(d.status), color: _statusColor(d.status)),
                    ],
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
    final body = _buildBody();
    if (widget.embedded) return body;
    return Scaffold(appBar: AppBar(title: const Text("Drivers")), body: body);
  }
}
