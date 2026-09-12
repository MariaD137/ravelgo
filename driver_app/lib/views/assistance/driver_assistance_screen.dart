import 'package:flutter/material.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';

/// Live hazard/route alerts ("Driver Assistance Mode") have no backend
/// behind them at all — no traffic or hazard data source is connected. This
/// used to show three permanently-present fabricated alerts naming real
/// Lagos streets (a speed trap, a road closure, a "12% fuel saved" route)
/// as if they were live — nothing here was ever real. Says so honestly
/// instead of presenting fiction as live safety information.
class DriverAssistanceScreen extends StatelessWidget {
  const DriverAssistanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Driver Assistance Mode")),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.alt_route_outlined, size: 48, color: AppColors.textMuted),
              const SizedBox(height: 16),
              const Text(
                "Live route & hazard alerts aren't available yet",
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
              ),
              const SizedBox(height: 8),
              const Text(
                "We don't have a live traffic or hazard data source connected, so there's nothing real to show here yet.",
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
