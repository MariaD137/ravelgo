import 'package:flutter/material.dart';
import 'package:ravelgo_driver_app/config/currency.dart';
import 'package:ravelgo_driver_app/services/driver_api.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';

/// Shown when the backend has matched a REAL trip to this driver (status
/// MATCHED). Accepting starts the trip on the backend; declining cancels it.
/// There is no fabricated countdown or fare "negotiation" here — the trip and
/// its fare are the backend's, and the two buttons drive real state changes
/// (P0 #3).
class IncomingRequestSheet extends StatelessWidget {
  final DriverTrip trip;
  final bool busy;
  const IncomingRequestSheet({super.key, required this.trip, this.busy = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("New ride request", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          Row(
            children: [
              const CircleAvatar(
                  radius: 22,
                  backgroundColor: AppColors.surfaceElevated,
                  child: Icon(Icons.person, color: AppColors.textSecondary)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(trip.riderName ?? 'Rider', style: const TextStyle(fontWeight: FontWeight.w600)),
                    if (trip.riderRating != null)
                      Row(children: [
                        const Icon(Icons.star, size: 14, color: AppColors.primary),
                        const SizedBox(width: 4),
                        Text(trip.riderRating!.toStringAsFixed(1),
                            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                      ]),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _row(Icons.trip_origin, trip.pickup),
          const SizedBox(height: 8),
          _row(Icons.place_outlined, trip.destination),
          if (trip.pickupNote != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(8)),
              child: Text('Pickup note: "${trip.pickupNote}"', style: const TextStyle(fontSize: 12.5)),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                trip.distanceKm != null ? "${trip.distanceKm!.toStringAsFixed(1)} km" : "Distance —",
                style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
              Text(
                Currency.format(trip.fare, decimals: 0),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (busy)
            const Center(child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator()))
          else
            Row(
              children: [
                Expanded(
                    child: AppComponents.outlineButton(
                        text: "Decline", onPressed: () => Navigator.pop(context, false))),
                const SizedBox(width: 12),
                Expanded(
                    child: AppComponents.primaryButton(
                        text: "Accept", onPressed: () => Navigator.pop(context, true))),
              ],
            ),
        ],
      ),
    );
  }

  Widget _row(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.textSecondary),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 13.5))),
      ],
    );
  }
}
