import 'package:flutter/material.dart';
import 'package:ravelgo_admin/models/trip_record.dart';
import 'package:ravelgo_admin/theme/app_theme.dart';
import 'package:ravelgo_admin/utils/date_utils.dart';
import 'package:ravelgo_admin/views/trips/trip_admin_detail_screen.dart';

class TripMonitoringScreen extends StatelessWidget {
  final bool embedded;
  const TripMonitoringScreen({super.key, this.embedded = false});

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
    final body = ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: mockTripRecords.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final t = mockTripRecords[i];
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
    );

    if (embedded) return body;
    return Scaffold(appBar: AppBar(title: const Text("Trips")), body: body);
  }
}
