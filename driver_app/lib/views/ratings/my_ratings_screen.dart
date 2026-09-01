import 'package:flutter/material.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';

class MyRatingsScreen extends StatelessWidget {
  const MyRatingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final reviews = [
      (5, "Great driver, very punctual", "2 days ago"),
      (5, "Smooth ride, friendly", "4 days ago"),
      (3, "Took a longer route than expected", "1 week ago"),
      (4, "Clean car", "2 weeks ago"),
    ];
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
                const Text("4.8", style: TextStyle(fontSize: 40, fontWeight: FontWeight.bold)),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(5, (i) => const Icon(Icons.star, color: AppColors.primaryDark, size: 18)),
                ),
                const SizedBox(height: 4),
                const Text("Based on 214 trips", style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          AppComponents.sectionTitle("Recent reviews (anonymous)"),
          ...reviews.map((r) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: AppComponents.cardDecoration(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          ...List.generate(r.$1, (i) => const Icon(Icons.star, size: 14, color: AppColors.primaryDark)),
                          ...List.generate(5 - r.$1, (i) => const Icon(Icons.star_border, size: 14, color: AppColors.textMuted)),
                          const Spacer(),
                          Text(r.$3, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(r.$2, style: const TextStyle(fontSize: 13)),
                    ],
                  ),
                ),
              )),
        ],
      ),
    );
  }
}
