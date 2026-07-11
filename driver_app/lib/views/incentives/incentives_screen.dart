import 'package:flutter/material.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';

class IncentivesScreen extends StatelessWidget {
  const IncentivesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final badges = [
      ("5-Star Streak", "Maintain a 5-star rating for 20 trips", true),
      ("Eco Driver", "Complete 10 eco-friendly rides", true),
      ("Weekend Warrior", "Complete 15 trips over a weekend", false),
      ("Century Club", "Complete 100 total trips", false),
    ];
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
          AppComponents.sectionTitle("Your badges"),
          ...badges.map((b) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: AppComponents.cardDecoration(),
                  child: Row(
                    children: [
                      Icon(b.$3 ? Icons.military_tech : Icons.military_tech_outlined, color: b.$3 ? AppColors.primaryDark : Colors.black26, size: 28),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(b.$1, style: const TextStyle(fontWeight: FontWeight.w600)),
                            Text(b.$2, style: const TextStyle(fontSize: 12, color: Colors.black54)),
                          ],
                        ),
                      ),
                      if (b.$3) AppComponents.badge("Earned", color: AppColors.success),
                    ],
                  ),
                ),
              )),
        ],
      ),
    );
  }
}
