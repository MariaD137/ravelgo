import 'package:flutter/material.dart';
import 'package:ravelgo_admin/models/admin_actions_state.dart';
import 'package:ravelgo_admin/models/fraud_alert.dart';
import 'package:ravelgo_admin/theme/app_theme.dart';
import 'package:ravelgo_admin/utils/date_utils.dart';

/// Live emergency (SOS) alerts.
/// LOCAL STATE ONLY: "Dispatch help" records the dispatch decision locally
/// and updates the card; it does NOT contact any responder - the dispatch
/// service is the integration point, and the confirmation says so.
class EmergencyAlertsScreen extends StatefulWidget {
  const EmergencyAlertsScreen({super.key});

  @override
  State<EmergencyAlertsScreen> createState() => _EmergencyAlertsScreenState();
}

class _EmergencyAlertsScreenState extends State<EmergencyAlertsScreen> {
  Future<void> _dispatch(EmergencyAlert e) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Dispatch help?'),
        content: Text(
            'Record a dispatch decision for ${e.personName} at ${e.location}? '
            'NOTE: the dispatch service is not connected in this build - no responder '
            'is contacted by this action.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Record dispatch', style: TextStyle(color: AppColors.danger))),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => AdminActionsState.instance.resolveEmergency(e.id));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Emergency Alerts")),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: mockEmergencyAlerts.map((e) {
          final handled = e.resolved || AdminActionsState.instance.resolvedEmergencies.contains(e.id);
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: AppComponents.cardDecoration(),
            child: Row(
              children: [
                Icon(Icons.sos, color: handled ? AppColors.textMuted : AppColors.danger, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("${e.personName} (${e.role})", style: const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text(e.location, style: const TextStyle(fontSize: 12.5)),
                      const SizedBox(height: 2),
                      Text(formatFriendlyDate(e.triggeredAt), style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                    ],
                  ),
                ),
                if (e.resolved)
                  AppComponents.badge("Resolved", color: AppColors.success)
                else if (handled)
                  AppComponents.badge("Dispatch recorded", color: AppColors.warning)
                else
                  ElevatedButton(
                    onPressed: () => _dispatch(e),
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger, foregroundColor: Colors.white),
                    child: const Text("Dispatch help"),
                  ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}
