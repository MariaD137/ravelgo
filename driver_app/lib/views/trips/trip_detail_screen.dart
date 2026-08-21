import 'package:flutter/material.dart';
import 'package:ravelgo_driver_app/models/trip.dart';
import 'package:ravelgo_driver_app/services/api_client.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';
import 'package:ravelgo_driver_app/utils/date_utils.dart';

class TripDetailScreen extends StatelessWidget {
  final Trip trip;
  const TripDetailScreen({super.key, required this.trip});

  Future<void> _reportLostItem(BuildContext context) async {
    try {
      await ApiClient().post('/support-tickets', body: {
        'subject': 'Lost Item',
        'category': 'LOST_ITEM',
        'tripId': trip.id,
      });

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lost item report submitted. Our support team will follow up.')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to submit report. Please try again or contact support.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cancelled = trip.status == TripStatus.cancelled;
    return Scaffold(
      appBar: AppBar(title: Text(trip.id)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppComponents.badge(cancelled ? "Cancelled" : "Completed", color: cancelled ? AppColors.danger : AppColors.success),
            const SizedBox(height: 12),
            Text(formatFriendlyDate(trip.date), style: const TextStyle(color: Colors.black54)),
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
                      const Text("Category"),
                      Text(trip.category, style: const TextStyle(fontWeight: FontWeight.w600)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("Fare", style: TextStyle(fontWeight: FontWeight.w700)),
                      Text(cancelled ? "N0" : "N${trip.fare.toStringAsFixed(0)}", style: const TextStyle(fontWeight: FontWeight.w700)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            AppComponents.outlineButton(
              text: "Download receipt",
              onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Feature coming soon")),
              ),
            ),
            const SizedBox(height: 12),
            AppComponents.outlineButton(
              text: "Report a lost item",
              onPressed: () => _reportLostItem(context),
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
