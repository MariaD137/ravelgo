import 'package:flutter/material.dart';
import 'package:ravelgo_driver_app/models/trip.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';
import 'package:ravelgo_driver_app/utils/date_utils.dart';
import 'package:ravelgo_driver_app/views/trips/trip_detail_screen.dart';

class MyTripsScreen extends StatelessWidget {
  final bool embedded;
  const MyTripsScreen({super.key, this.embedded = false});

  @override
  Widget build(BuildContext context) {
    final body = SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (embedded) AppComponents.sectionTitle("My Trips"),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: mockTrips.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final t = mockTrips[i];
                final cancelled = t.status == TripStatus.cancelled;
                return InkWell(
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TripDetailScreen(trip: t))),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: AppComponents.cardDecoration(),
                    child: Row(
                      children: [
                        Icon(cancelled ? Icons.cancel_outlined : Icons.check_circle_outline,
                            color: cancelled ? AppColors.danger : AppColors.success),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("${t.pickup} → ${t.destination}", style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                              const SizedBox(height: 4),
                              Text(formatFriendlyDate(t.date), style: const TextStyle(fontSize: 12, color: Colors.black54)),
                            ],
                          ),
                        ),
                        Text(
                          cancelled ? "Cancelled" : "₦${t.fare.toStringAsFixed(0)}",
                          style: TextStyle(fontWeight: FontWeight.w700, color: cancelled ? AppColors.danger : Colors.black),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );

    if (embedded) return body;
    return Scaffold(appBar: AppBar(title: const Text("My Trips")), body: body);
  }
}
