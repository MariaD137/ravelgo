import 'package:flutter/material.dart';
import 'package:ravelgo_driver_app/services/driver_session.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';

/// The overall rating/trip count are real (Driver.rating/totalTrips, from
/// the same profile DriverShell already loaded before this screen is
/// reachable). Per-trip written reviews have no backend model yet — no
/// endpoint exists for a rider to leave one, and DriverDocument/Trip carry
/// no review text field — so that section is shown as an honest "not
/// available yet" rather than fabricated review text.
class MyRatingsScreen extends StatelessWidget {
  const MyRatingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final profile = DriverSession.instance.profile!;
    return Scaffold(
      appBar: AppBar(title: const Text("My Ratings")),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: AppComponents.cardDecoration(),
            child: Column(
              children: [
                Text(profile.rating.toStringAsFixed(1), style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold)),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(5, (i) {
                    final threshold = i + 1;
                    final filled = profile.rating >= threshold - 0.5;
                    return Icon(filled ? Icons.star : Icons.star_border, color: AppColors.primaryDark, size: 18);
                  }),
                ),
                const SizedBox(height: 4),
                Text("Based on ${profile.totalTrips} trips", style: const TextStyle(fontSize: 12, color: Colors.black54)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          AppComponents.sectionTitle("Recent reviews"),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: AppComponents.cardDecoration(),
            child: const Text(
              "Written trip reviews aren't available yet — this screen shows your real overall rating and trip count above.",
              style: TextStyle(fontSize: 13, color: Colors.black54),
            ),
          ),
        ],
      ),
    );
  }
}
