import 'package:flutter/material.dart';
import 'package:ravelgo_admin/models/admin_actions_state.dart';
import 'package:ravelgo_admin/models/fraud_alert.dart';
import 'package:ravelgo_admin/theme/app_theme.dart';
import 'package:ravelgo_admin/utils/date_utils.dart';

/// Fraud alerts with working dismiss/investigate.
/// LOCAL STATE ONLY: decisions are recorded in AdminActionsState and the
/// card updates; persisting them is the safety-API integration point.
class FraudAlertsScreen extends StatefulWidget {
  const FraudAlertsScreen({super.key});

  @override
  State<FraudAlertsScreen> createState() => _FraudAlertsScreenState();
}

class _FraudAlertsScreenState extends State<FraudAlertsScreen> {
  Future<void> _dismiss(FraudAlert a) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Dismiss alert?'),
        content: Text('Dismiss "${a.title}" (${a.id}) as a false positive?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Dismiss')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => AdminActionsState.instance.decideFraud(a.id, 'dismissed'));
  }

  void _investigate(FraudAlert a) {
    setState(() => AdminActionsState.instance.decideFraud(a.id, 'investigating'));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('${a.id} marked under investigation (recorded locally)'),
    ));
  }

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
          ...mockFraudAlerts.map((a) {
            final decision = AdminActionsState.instance.fraudDecisions[a.id];
            return Container(
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
                    Text(a.description, style: const TextStyle(fontSize: 13, color: AppColors.textPrimary)),
                    const SizedBox(height: 6),
                    Text(formatFriendlyDate(a.detectedAt), style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                    const SizedBox(height: 10),
                    if (decision == 'dismissed')
                      AppComponents.badge('Dismissed', color: AppColors.textMuted)
                    else if (decision == 'investigating')
                      AppComponents.badge('Under investigation', color: AppColors.warning)
                    else
                      Row(
                        children: [
                          Expanded(
                              child: AppComponents.outlineButton(
                                  text: "Dismiss", onPressed: () => _dismiss(a))),
                          const SizedBox(width: 10),
                          Expanded(
                              child: AppComponents.outlineButton(
                                  text: "Investigate",
                                  color: AppColors.danger,
                                  onPressed: () => _investigate(a))),
                        ],
                      ),
                  ],
                ),
              );
          }),
        ],
      ),
    );
  }
}
