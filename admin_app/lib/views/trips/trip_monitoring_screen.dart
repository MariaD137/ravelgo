import 'package:flutter/material.dart';
import 'package:ravelgo_admin/models/trip_record.dart';
import 'package:ravelgo_admin/services/api_client.dart';
import 'package:ravelgo_admin/theme/app_theme.dart';
import 'package:ravelgo_admin/utils/date_utils.dart';
import 'package:ravelgo_admin/views/trips/trip_admin_detail_screen.dart';

class TripMonitoringScreen extends StatefulWidget {
  final bool embedded;
  const TripMonitoringScreen({super.key, this.embedded = false});

  @override
  State<TripMonitoringScreen> createState() => _TripMonitoringScreenState();
}

class _TripMonitoringScreenState extends State<TripMonitoringScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _trips = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final response = await ApiClient().get('/trips');
      final page = response as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _trips = List<Map<String, dynamic>>.from(page['data'] ?? []);
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

  TripRecord _toTripRecord(Map<String, dynamic> json) {
    final rider = json['rider'] as Map<String, dynamic>? ?? {};
    final driver = json['driver'] as Map<String, dynamic>?;
    final driverUser = driver != null ? (driver['user'] as Map<String, dynamic>? ?? {}) : {};

    final statusStr = json['status'] as String? ?? 'REQUESTED';
    TripRecordStatus status;
    switch (statusStr) {
      case 'IN_PROGRESS':
      case 'MATCHED':
      case 'REQUESTED':
        status = TripRecordStatus.inProgress;
        break;
      case 'COMPLETED':
        status = TripRecordStatus.completed;
        break;
      case 'CANCELLED':
        status = TripRecordStatus.cancelled;
        break;
      case 'DISPUTED':
        status = TripRecordStatus.disputed;
        break;
      default:
        status = TripRecordStatus.inProgress;
    }

    DateTime date;
    if (json['requestedAt'] != null) {
      date = DateTime.tryParse(json['requestedAt'].toString()) ?? DateTime.now();
    } else {
      date = DateTime.now();
    }

    return TripRecord(
      id: json['id'] ?? '',
      riderName: '${rider['firstName'] ?? ''} ${rider['lastName'] ?? ''}'.trim(),
      driverName: driver != null
          ? '${driverUser['firstName'] ?? ''} ${driverUser['lastName'] ?? ''}'.trim()
          : 'Unassigned',
      pickup: json['pickup'] ?? '',
      destination: json['destination'] ?? '',
      fare: (json['finalFare'] ?? json['estimatedFare'] ?? 0).toDouble(),
      date: date,
      status: status,
    );
  }

  Color _statusColor(TripRecordStatus s) {
    switch (s) {
      case TripRecordStatus.inProgress:
        return AppColors.info;
      case TripRecordStatus.completed:
        return AppColors.success;
      case TripRecordStatus.cancelled:
        return Colors.grey;
      case TripRecordStatus.disputed:
        return AppColors.danger;
    }
  }

  String _statusLabel(TripRecordStatus s) {
    switch (s) {
      case TripRecordStatus.inProgress:
        return "In progress";
      case TripRecordStatus.completed:
        return "Completed";
      case TripRecordStatus.cancelled:
        return "Cancelled";
      case TripRecordStatus.disputed:
        return "Disputed";
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      final loader = const Center(child: CircularProgressIndicator());
      if (widget.embedded) return loader;
      return Scaffold(appBar: AppBar(title: const Text("Trips")), body: loader);
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
              Text('Failed to load trips', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(fontSize: 12, color: Colors.black54), textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: () { setState(() { _loading = true; _error = null; }); _loadData(); }, child: const Text("Retry")),
            ],
          ),
        ),
      );
      if (widget.embedded) return errorView;
      return Scaffold(appBar: AppBar(title: const Text("Trips")), body: errorView);
    }

    final body = RefreshIndicator(
      onRefresh: _loadData,
      child: _trips.isEmpty
          ? ListView(children: const [SizedBox(height: 100), Center(child: Text("No trips found", style: TextStyle(color: Colors.black54)))])
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _trips.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final t = _toTripRecord(_trips[i]);
                return InkWell(
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TripAdminDetailScreen(trip: t))),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: AppComponents.cardDecoration(),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("${t.riderName}  →  ${t.driverName}", style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                              const SizedBox(height: 4),
                              Text("${t.pickup} to ${t.destination}", style: const TextStyle(fontSize: 12, color: Colors.black54)),
                              const SizedBox(height: 2),
                              Text(formatFriendlyDate(t.date), style: const TextStyle(fontSize: 11, color: Colors.black45)),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            AppComponents.badge(_statusLabel(t.status), color: _statusColor(t.status)),
                            const SizedBox(height: 6),
                            Text("₦${t.fare.toStringAsFixed(0)}", style: const TextStyle(fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );

    if (widget.embedded) return body;
    return Scaffold(appBar: AppBar(title: const Text("Trips")), body: body);
  }
}
