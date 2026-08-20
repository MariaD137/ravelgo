import 'package:flutter/material.dart';
import 'package:ravelgo_admin/models/driver_record.dart';
import 'package:ravelgo_admin/services/api_client.dart';
import 'package:ravelgo_admin/theme/app_theme.dart';
import 'package:ravelgo_admin/views/drivers/driver_detail_screen.dart';

class DriverListScreen extends StatefulWidget {
  final bool embedded;
  const DriverListScreen({super.key, this.embedded = false});

  @override
  State<DriverListScreen> createState() => _DriverListScreenState();
}

class _DriverListScreenState extends State<DriverListScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _drivers = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final response = await ApiClient().get('/drivers');
      final page = response as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _drivers = List<Map<String, dynamic>>.from(page['data'] ?? []);
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

  DriverRecord _toDriverRecord(Map<String, dynamic> json) {
    final user = json['user'] as Map<String, dynamic>? ?? {};
    final vehicles = json['vehicles'] as List? ?? [];
    final statusStr = json['status'] as String? ?? 'PENDING_REVIEW';
    DriverStatus status;
    switch (statusStr) {
      case 'ACTIVE':
        status = DriverStatus.active;
        break;
      case 'SUSPENDED':
        status = DriverStatus.suspended;
        break;
      default:
        status = DriverStatus.pendingReview;
    }

    String vehicle = 'No vehicle';
    if (vehicles.isNotEmpty) {
      final v = vehicles[0] as Map<String, dynamic>;
      vehicle = '${v['brand'] ?? ''} ${v['model'] ?? ''}'.trim();
    }

    return DriverRecord(
      id: json['id'] ?? '',
      name: '${user['firstName'] ?? ''} ${user['lastName'] ?? ''}'.trim(),
      email: user['email'] ?? '',
      vehicle: vehicle,
      rating: (json['rating'] ?? 5.0).toDouble(),
      totalTrips: json['totalTrips'] ?? 0,
      status: status,
      subscriptionActive: json['subscriptionActive'] == true,
    );
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
    if (_loading) {
      final loader = const Center(child: CircularProgressIndicator());
      if (widget.embedded) return loader;
      return Scaffold(appBar: AppBar(title: const Text("Drivers")), body: loader);
    }

    if (_error != null) {
      final errorView = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 12),
              Text('Failed to load drivers', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(fontSize: 12, color: Colors.black54), textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: () { setState(() { _loading = true; _error = null; }); _loadData(); }, child: const Text("Retry")),
            ],
          ),
        ),
      );
      if (widget.embedded) return errorView;
      return Scaffold(appBar: AppBar(title: const Text("Drivers")), body: errorView);
    }

    final body = RefreshIndicator(
      onRefresh: _loadData,
      child: _drivers.isEmpty
          ? ListView(children: const [SizedBox(height: 100), Center(child: Text("No drivers found", style: TextStyle(color: Colors.black54)))])
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _drivers.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final d = _toDriverRecord(_drivers[i]);
                return InkWell(
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DriverDetailScreen(driver: d))),
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
            ),
    );

    if (widget.embedded) return body;
    return Scaffold(appBar: AppBar(title: const Text("Drivers")), body: body);
  }
}
