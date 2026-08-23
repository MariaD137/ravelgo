import 'package:flutter/material.dart';
import 'package:ravelgo_admin/models/trip_record.dart';
import 'package:ravelgo_admin/services/api/api_client.dart';
import 'package:ravelgo_admin/services/api/trip_api.dart';
import 'package:ravelgo_admin/theme/app_theme.dart';
import 'package:ravelgo_admin/utils/date_utils.dart';
import 'package:ravelgo_admin/views/trips/trip_admin_detail_screen.dart';

class TripMonitoringScreen extends StatefulWidget {
  final bool embedded;
  final TripApi? tripApi;
  const TripMonitoringScreen({super.key, this.embedded = false, this.tripApi});

  @override
  State<TripMonitoringScreen> createState() => _TripMonitoringScreenState();
}

class _TripMonitoringScreenState extends State<TripMonitoringScreen> {
  late final TripApi _api = widget.tripApi ?? TripApi(ApiClient());
  late Future<List<TripRecord>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<TripRecord>> _load() async {
    final raw = await _api.listAll();
    return raw.map(TripRecord.fromJson).toList();
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  Color _statusColor(TripRecordStatus s) {
    switch (s) {
      case TripRecordStatus.requested:
        return Colors.grey;
      case TripRecordStatus.matched:
        return AppColors.info;
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
      case TripRecordStatus.requested:
        return "Requested";
      case TripRecordStatus.matched:
        return "Matched";
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
    final body = RefreshIndicator(
      onRefresh: _refresh,
      child: FutureBuilder<List<TripRecord>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return ListView(
              children: [
                const SizedBox(height: 80),
                Center(child: Text('Failed to load trips: ${snapshot.error}', textAlign: TextAlign.center)),
                const SizedBox(height: 12),
                Center(child: TextButton(onPressed: _refresh, child: const Text('Retry'))),
              ],
            );
          }
          final trips = snapshot.data ?? const [];
          if (trips.isEmpty) {
            return ListView(
              children: const [
                SizedBox(height: 80),
                Center(child: Text('No trips yet.', style: TextStyle(color: Colors.black54))),
              ],
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: trips.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final t = trips[i];
              return InkWell(
                onTap: () async {
                  final changed = await Navigator.push<bool>(
                    context,
                    MaterialPageRoute(builder: (_) => TripAdminDetailScreen(tripId: t.id, tripApi: _api)),
                  );
                  if (changed == true) _refresh();
                },
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
          );
        },
      ),
    );

    if (widget.embedded) return body;
    return Scaffold(appBar: AppBar(title: const Text("Trips")), body: body);
  }
}
