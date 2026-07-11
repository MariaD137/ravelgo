import 'package:flutter/material.dart';
import 'package:ravelgo_admin/models/fraud_alert.dart';
import 'package:ravelgo_admin/theme/app_theme.dart';
import 'package:ravelgo_admin/utils/date_utils.dart';

class EmergencyAlertsScreen extends StatelessWidget {
  const EmergencyAlertsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Emergency Alerts")),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: mockEmergencyAlerts.map((e) {
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: AppComponents.cardDecoration(),
            child: Row(
              children: [
                Icon(Icons.sos, color: e.resolved ? Colors.grey : AppColors.danger, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("${e.personName} (${e.role})", style: const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text(e.location, style: const TextStyle(fontSize: 12.5)),
                      const SizedBox(height: 2),
                      Text(formatFriendlyDate(e.triggeredAt), style: const TextStyle(fontSize: 11, color: Colors.black45)),
                    ],
                  ),
                ),
                if (e.resolved)
                  AppComponents.badge("Resolved", color: AppColors.success)
                else
                  ElevatedButton(
                    onPressed: () {},
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
