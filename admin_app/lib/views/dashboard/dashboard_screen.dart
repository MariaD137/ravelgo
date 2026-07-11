import 'package:flutter/material.dart';
import 'package:ravelgo_admin/models/trip_record.dart';
import 'package:ravelgo_admin/theme/app_theme.dart';
import 'package:ravelgo_admin/utils/date_utils.dart';

class DashboardScreen extends StatelessWidget {
  final bool embedded;
  const DashboardScreen({super.key, this.embedded = false});

  static const _rides = [128.0, 142.0, 96.0, 180.0, 210.0, 260.0, 174.0];
  static const _days = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];

  @override
  Widget build(BuildContext context) {
    final maxVal = _rides.reduce((a, b) => a > b ? a : b);
    final body = ListView(
      padding: const EdgeInsets.all(16),
      children: [
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.5,
          children: [
            AppComponents.statCard("Active rides now", "24", Icons.directions_car_filled_outlined),
            AppComponents.statCard("Online drivers", "112", Icons.badge_outlined, color: AppColors.success),
            AppComponents.statCard("Revenue today", "₦482,300", Icons.payments_outlined, color: AppColors.info),
            AppComponents.statCard("Pending approvals", "7", Icons.pending_actions_outlined, color: AppColors.warning),
          ],
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: AppComponents.cardDecoration(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Rides this week", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              const SizedBox(height: 16),
              SizedBox(
                height: 120,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: List.generate(_rides.length, (i) {
                    final h = 100 * (_rides[i] / maxVal);
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Container(
                              height: h,
                              decoration: BoxDecoration(
                                color: i == _rides.length - 1 ? AppColors.primary : AppColors.primary.withValues(alpha: 0.35),
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(_days[i], style: const TextStyle(fontSize: 11, color: Colors.black54)),
                          ],
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        AppComponents.sectionTitle("Recent trips"),
        ...mockTripRecords.take(4).map((t) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
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
                          Text("${t.pickup} to ${t.destination} · ${formatFriendlyDate(t.date)}", style: const TextStyle(fontSize: 11.5, color: Colors.black54)),
                        ],
                      ),
                    ),
                    Text("₦${t.fare.toStringAsFixed(0)}", style: const TextStyle(fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            )),
      ],
    );

    if (embedded) return body;
    return Scaffold(appBar: AppBar(title: const Text("Dashboard")), body: body);
  }
}
