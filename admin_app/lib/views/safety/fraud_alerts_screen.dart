import 'package:flutter/material.dart';
import 'package:ravelgo_admin/models/fraud_alert.dart';
import 'package:ravelgo_admin/theme/app_theme.dart';
import 'package:ravelgo_admin/utils/date_utils.dart';

class FraudAlertsScreen extends StatelessWidget {
  const FraudAlertsScreen({super.key});

  Color _severityColor(AlertSeverity s) {
    switch (s) {
      case AlertSeverity.low:
        return AppColors.success;
      case AlertSeverity.medium:
        return AppColors.warning;
      case AlertSeverity.high:
        return AppColors.danger;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Fraud Alerts")),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
            child: const Text(
              "AI-based fraud prevention flags unusual booking patterns or ride behavior for your review.",
              style: TextStyle(fontSize: 12.5),
            ),
          ),
          ...mockFraudAlerts.map((a) => Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: AppComponents.cardDecoration(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(child: Text(a.title, style: const TextStyle(fontWeight: FontWeight.w700))),
                        AppComponents.badge(a.severity.name, color: _severityColor(a.severity)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(a.description, style: const TextStyle(fontSize: 13, color: Colors.black87)),
                    const SizedBox(height: 6),
                    Text(formatFriendlyDate(a.detectedAt), style: const TextStyle(fontSize: 11, color: Colors.black45)),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(child: AppComponents.outlineButton(text: "Dismiss", onPressed: () {})),
                        const SizedBox(width: 10),
                        Expanded(child: AppComponents.outlineButton(text: "Investigate", color: AppColors.danger, onPressed: () {})),
                      ],
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}
