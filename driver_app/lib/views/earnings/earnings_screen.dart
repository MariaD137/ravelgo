import 'package:flutter/material.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';

class EarningsScreen extends StatelessWidget {
  final bool embedded;
  const EarningsScreen({super.key, this.embedded = false});

  static const _week = [12000.0, 18500.0, 9000.0, 22000.0, 15600.0, 27400.0, 18400.0];
  static const _days = ["M", "T", "W", "T", "F", "S", "S"];
  static const _chartBarMaxHeight = 100.0;

  @override
  Widget build(BuildContext context) {
    final maxVal = _week.reduce((a, b) => a > b ? a : b);
    final body = SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (embedded) AppComponents.sectionTitle("Earnings"),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: AppComponents.cardDecoration(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("This week", style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                const SizedBox(height: 4),
                Text("₦${_week.reduce((a, b) => a + b).toStringAsFixed(0)}",
                    style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                const SizedBox(height: 20),
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: List.generate(_week.length, (i) {
                      final h = _chartBarMaxHeight * (_week[i] / maxVal);
                      return Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Container(
                                height: h,
                                decoration: BoxDecoration(
                                  color: i == _week.length - 1 ? AppColors.primary : AppColors.primary.withValues(alpha: 0.35),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(_days[i], style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
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
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: AppComponents.statChip("Trips completed", "38")),
              const SizedBox(width: 12),
              Expanded(child: AppComponents.statChip("Avg. rating", "4.8")),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            decoration: AppComponents.cardDecoration(),
            child: Column(
              children: [
                AppComponents.tile(title: "Cash out to bank", subtitle: "Instant transfer to linked account", leading: Icons.account_balance_outlined, onTap: () {}),
                AppComponents.divider(),
                AppComponents.tile(title: "Payout history", subtitle: "View past transfers", leading: Icons.history, onTap: () {}),
                AppComponents.divider(),
                AppComponents.tile(title: "Skill-based incentives", subtitle: "Bonuses for milestones & ratings", leading: Icons.emoji_events_outlined, onTap: () {}),
              ],
            ),
          ),
        ],
      ),
    );

    if (embedded) return body;
    return Scaffold(appBar: AppBar(title: const Text("Earnings")), body: body);
  }
}
