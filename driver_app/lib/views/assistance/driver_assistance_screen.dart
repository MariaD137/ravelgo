import 'package:flutter/material.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';

class DriverAssistanceScreen extends StatelessWidget {
  const DriverAssistanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final alerts = [
      ("Speed trap ahead", "Reported 400m ahead on Admiralty Way", Icons.speed),
      ("Road construction", "Lane closure on Ozumba Mbadiwe Ave", Icons.construction),
      ("Fuel-efficient route available", "Save ~6 minutes and 12% fuel via Osborne Rd", Icons.local_gas_station_outlined),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text("Driver Assistance Mode")),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            "AI-powered tools suggest fuel-efficient routes and warn you about hazards, speed traps and construction zones in real time.",
            style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 20),
          ...alerts.map((a) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: AppComponents.cardDecoration(),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(color: AppColors.border.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(10)),
                        child: Icon(a.$3, color: AppColors.textSecondary),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(a.$1, style: const TextStyle(fontWeight: FontWeight.w600)),
                            const SizedBox(height: 2),
                            Text(a.$2, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              )),
        ],
      ),
    );
  }
}
