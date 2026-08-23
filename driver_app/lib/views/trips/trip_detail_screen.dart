import 'package:flutter/material.dart';
import 'package:ravelgo_driver_app/models/trip.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';
import 'package:ravelgo_driver_app/utils/date_utils.dart';

class TripDetailScreen extends StatelessWidget {
  final Trip trip;
  const TripDetailScreen({super.key, required this.trip});

  @override
  Widget build(BuildContext context) {
    final cancelled = trip.isCancelled;
    return Scaffold(
      appBar: AppBar(title: Text(trip.id)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppComponents.badge(cancelled ? "Cancelled" : trip.status, color: cancelled ? AppColors.danger : AppColors.success),
            const SizedBox(height: 12),
            Text(formatFriendlyDate(trip.requestedAt), style: const TextStyle(color: Colors.black54)),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: AppComponents.cardDecoration(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _row(Icons.trip_origin, trip.pickup),
                  const SizedBox(height: 10),
                  _row(Icons.place_outlined, trip.destination),
                  AppComponents.divider(),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("Rider"),
                        Text(trip.riderName, style: const TextStyle(fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("Fare", style: TextStyle(fontWeight: FontWeight.w700)),
                      Text(cancelled ? "₦0" : "₦${trip.fare.toStringAsFixed(0)}", style: const TextStyle(fontWeight: FontWeight.w700)),
                    ],
                  ),
                ],
              ),
            ),
            // Neither a per-driver receipt download nor a lost-item report
            // has a real backend endpoint yet (payments.routes.ts's receipt
            // route exists for a Payment id, not a Trip id, and isn't
            // reachable from here) — shown as an honest "not available yet"
            // rather than a fake success message.
            const SizedBox(height: 20),
            AppComponents.outlineButton(
              text: "Download receipt",
              onPressed: () => ScaffoldMessenger.of(context)
                  .showSnackBar(const SnackBar(content: Text("Receipts aren't available from this screen yet"))),
            ),
            const SizedBox(height: 12),
            AppComponents.outlineButton(
              text: "Report a lost item",
              onPressed: () => ScaffoldMessenger.of(context)
                  .showSnackBar(const SnackBar(content: Text("Lost item reporting isn't available yet"))),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: Colors.black54),
        const SizedBox(width: 8),
        Expanded(child: Text(text)),
      ],
    );
  }
}
