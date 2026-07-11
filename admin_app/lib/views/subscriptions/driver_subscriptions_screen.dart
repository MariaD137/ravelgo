import 'package:flutter/material.dart';
import 'package:ravelgo_admin/models/driver_record.dart';
import 'package:ravelgo_admin/theme/app_theme.dart';

class DriverSubscriptionsScreen extends StatelessWidget {
  const DriverSubscriptionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final subscribed = mockDrivers.where((d) => d.subscriptionActive).length;
    return Scaffold(
      appBar: AppBar(title: const Text("Driver Subscriptions")),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Row(
            children: [
              Expanded(child: AppComponents.statCard("Subscribed drivers", "$subscribed", Icons.workspace_premium_outlined, color: AppColors.success)),
              const SizedBox(width: 12),
              Expanded(child: AppComponents.statCard("Monthly plan revenue", "₦1,284,000", Icons.payments_outlined, color: AppColors.info)),
            ],
          ),
          const SizedBox(height: 20),
          AppComponents.sectionTitle("Plans"),
          Container(
            decoration: AppComponents.cardDecoration(),
            child: Column(
              children: [
                AppComponents.tile(title: "Weekly", subtitle: "₦3,500 / week", leading: Icons.calendar_view_week, onTap: () {}),
                AppComponents.divider(),
                AppComponents.tile(title: "Monthly", subtitle: "₦12,000 / month", leading: Icons.calendar_month_outlined, onTap: () {}),
                AppComponents.divider(),
                AppComponents.tile(title: "Quarterly", subtitle: "₦32,000 / quarter", leading: Icons.event_repeat_outlined, onTap: () {}),
              ],
            ),
          ),
          const SizedBox(height: 20),
          AppComponents.sectionTitle("Drivers"),
          ...mockDrivers.map((d) => Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: AppComponents.cardDecoration(),
                child: Row(
                  children: [
                    Expanded(child: Text(d.name, style: const TextStyle(fontWeight: FontWeight.w600))),
                    AppComponents.badge(
                      d.subscriptionActive ? "Subscribed" : "Not subscribed",
                      color: d.subscriptionActive ? AppColors.success : Colors.grey,
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}
