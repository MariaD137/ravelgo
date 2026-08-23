import 'package:flutter/material.dart';
import 'package:ravelgo_admin/models/driver_record.dart';
import 'package:ravelgo_admin/services/api/api_client.dart';
import 'package:ravelgo_admin/services/api/driver_api.dart';
import 'package:ravelgo_admin/theme/app_theme.dart';
import 'package:ravelgo_admin/views/drivers/driver_detail_screen.dart';

class DriverListScreen extends StatefulWidget {
  final bool embedded;
  final DriverApi? driverApi;
  const DriverListScreen({super.key, this.embedded = false, this.driverApi});

  @override
  State<DriverListScreen> createState() => _DriverListScreenState();
}

class _DriverListScreenState extends State<DriverListScreen> {
  late final DriverApi _api = widget.driverApi ?? DriverApi(ApiClient());
  late Future<List<DriverRecord>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<DriverRecord>> _load() async {
    final raw = await _api.listDrivers();
    return raw.map(DriverRecord.fromJson).toList();
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  Color _statusColor(DriverStatus s) {
    switch (s) {
      case DriverStatus.active:
        return AppColors.success;
      case DriverStatus.pendingReview:
        return AppColors.warning;
      case DriverStatus.suspended:
        return AppColors.danger;
    }
  }

  String _statusLabel(DriverStatus s) {
    switch (s) {
      case DriverStatus.active:
        return "Active";
      case DriverStatus.pendingReview:
        return "Pending review";
      case DriverStatus.suspended:
        return "Suspended";
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = RefreshIndicator(
      onRefresh: _refresh,
      child: FutureBuilder<List<DriverRecord>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return ListView(
              children: [
                const SizedBox(height: 80),
                Icon(Icons.error_outline, size: 40, color: AppColors.danger),
                const SizedBox(height: 12),
                Center(child: Text('Failed to load drivers: ${snapshot.error}', textAlign: TextAlign.center)),
                const SizedBox(height: 12),
                Center(child: TextButton(onPressed: _refresh, child: const Text('Retry'))),
              ],
            );
          }
          final drivers = snapshot.data ?? const [];
          if (drivers.isEmpty) {
            return ListView(
              children: const [
                SizedBox(height: 80),
                Center(child: Text('No drivers yet.', style: TextStyle(color: Colors.black54))),
              ],
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: drivers.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final d = drivers[i];
              return InkWell(
                onTap: () async {
                  final changed = await Navigator.push<bool>(
                    context,
                    MaterialPageRoute(builder: (_) => DriverDetailScreen(driverId: d.id, driverApi: _api)),
                  );
                  if (changed == true) _refresh();
                },
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
                            Text(d.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                            const SizedBox(height: 4),
                            Text("${d.vehicle} · ${d.totalTrips} trips · ★ ${d.rating}", style: const TextStyle(fontSize: 12, color: Colors.black54)),
                          ],
                        ),
                      ),
                      AppComponents.badge(_statusLabel(d.status), color: _statusColor(d.status)),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );

    if (widget.embedded) return body;
    return Scaffold(appBar: AppBar(title: const Text("Drivers")), body: body);
  }
}
