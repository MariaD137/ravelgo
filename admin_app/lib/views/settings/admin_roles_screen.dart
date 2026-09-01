import 'package:flutter/material.dart';
import 'package:ravelgo_admin/theme/app_theme.dart';

class AdminRolesScreen extends StatelessWidget {
  const AdminRolesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final roles = [
      ("Super Admin", "Full access to all modules", ["Ops Admin"]),
      ("Operations Manager", "Drivers, trips, pricing, support", ["Kunle Ade", "Bisi Adewale"]),
      ("Support Agent", "Support tickets, disputes, lost items only", ["Ngozi Adeyemi"]),
      ("Finance Viewer", "Read-only access to revenue & subscriptions", ["Femi Coker"]),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text("Admin Roles")),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: roles.map((r) {
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: AppComponents.cardDecoration(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r.$1, style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(r.$2, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: r.$3.map((n) => AppComponents.badge(n)).toList(),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}
