import 'package:flutter/material.dart';
import 'package:ravelgo_admin/models/driver_record.dart';
import 'package:ravelgo_admin/theme/app_theme.dart';
import 'package:ravelgo_admin/views/drivers/driver_detail_screen.dart';

class DriverListScreen extends StatelessWidget {
  final bool embedded;
  const DriverListScreen({super.key, this.embedded = false});

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
    final body = ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: mockDrivers.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final d = mockDrivers[i];
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
    );

    if (embedded) return body;
    return Scaffold(appBar: AppBar(title: const Text("Drivers")), body: body);
  }
}
