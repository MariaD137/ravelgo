import 'package:flutter/material.dart';
import 'package:ravelgo_driver_app/services/api_client.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';

class EmergencyScreen extends StatelessWidget {
  final String? currentTripId;
  const EmergencyScreen({super.key, this.currentTripId});

  Future<void> _sendSOS(BuildContext context) async {
    try {
      await ApiClient().post('/emergency-alerts', body: {
        'type': 'SOS',
        if (currentTripId != null) 'tripId': currentTripId,
      });

      if (!context.mounted) return;
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text("SOS sent"),
          content: const Text("Your live location and trip details have been shared with RavelGo's safety team and your trusted contacts."),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("OK"))],
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text("Emergency alert"),
          content: const Text("Failed to send SOS alert. Please call emergency services directly if you are in danger."),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("OK"))],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Safety & Emergency")),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: AppColors.danger.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(16)),
            child: Column(
              children: [
                const Icon(Icons.shield, color: AppColors.danger, size: 40),
                const SizedBox(height: 10),
                const Text("In an emergency, alert RavelGo Safety immediately", textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: () => _sendSOS(context),
                    icon: const Icon(Icons.sos),
                    label: const Text("SOS – Emergency assistance"),
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger, foregroundColor: Colors.white),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Container(
            decoration: AppComponents.cardDecoration(),
            child: Column(
              children: [
                AppComponents.tile(title: "Trusted contacts", subtitle: "Share live trip details automatically", leading: Icons.people_outline, onTap: () {}),
                AppComponents.divider(),
                AppComponents.tile(title: "Emergency ride scheduling", subtitle: "Priority routing to hospitals & safe zones", leading: Icons.local_hospital_outlined, onTap: () {}),
                AppComponents.divider(),
                AppComponents.tile(title: "Fraud & suspicious activity", subtitle: "Report unusual booking behavior", leading: Icons.warning_amber_outlined, onTap: () {}),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
