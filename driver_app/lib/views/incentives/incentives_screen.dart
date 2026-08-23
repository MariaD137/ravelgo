import 'package:flutter/material.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';

/// There is no backend model for incentives/badges/achievements yet (no
/// endpoint, no schema table) — the previous version of this screen showed
/// a fixed, fabricated list of "earned"/"not earned" badges regardless of
/// the signed-in driver's real activity. Rather than invent that backend
/// capability or keep faking it client-side, this screen stays in place
/// (so the product surface isn't silently deleted) but says plainly that
/// it isn't available yet.
class IncentivesScreen extends StatelessWidget {
  const IncentivesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Incentives & Badges")),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: AppComponents.cardDecoration(),
            child: Row(
              children: [
                const Icon(Icons.emoji_events, color: AppColors.primaryDark, size: 32),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text("Earn bonuses and badges for excellent ratings and eco-friendly rides.", style: TextStyle(fontSize: 13.5)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: AppComponents.cardDecoration(),
            child: const Text(
              "Incentives and badges aren't available yet — check back once this feature launches.",
              style: TextStyle(fontSize: 13, color: Colors.black54),
            ),
          ),
        ],
      ),
    );
  }
}
