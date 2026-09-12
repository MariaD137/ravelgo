import 'package:flutter/material.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';

/// A driver rewards/badges program is not built yet — there is no
/// CommissionConfig-style backend model for it, no endpoint, and no way to
/// know which milestones a driver has actually hit. This used to show four
/// hardcoded badges (two always "Earned") to every driver regardless of
/// their real trip history — a fabricated achievement. Says so honestly
/// instead.
class IncentivesScreen extends StatelessWidget {
  const IncentivesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Incentives & Badges")),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.emoji_events_outlined, size: 48, color: AppColors.textMuted),
              const SizedBox(height: 16),
              const Text(
                "Incentives & badges aren't available yet",
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
              ),
              const SizedBox(height: 8),
              const Text(
                "We're not running a rewards program yet, so there's nothing to show here. Your earnings and trip history are always in Earnings and My Ratings.",
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
