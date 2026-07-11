import 'package:flutter/material.dart';
import 'package:ravelgo_admin/models/rider_record.dart';
import 'package:ravelgo_admin/theme/app_theme.dart';
import 'package:ravelgo_admin/views/riders/rider_detail_screen.dart';

class RiderListScreen extends StatelessWidget {
  const RiderListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Riders")),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: mockRiders.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          final r = mockRiders[i];
          return InkWell(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => RiderDetailScreen(rider: r))),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: AppComponents.cardDecoration(),
              child: Row(
                children: [
                  const CircleAvatar(radius: 22, backgroundColor: Color(0xFFF0F0F0), child: Icon(Icons.person, color: Colors.black45)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Text(r.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                          if (r.isLoyaltyMember) ...[const SizedBox(width: 6), AppComponents.badge("Loyalty")],
                        ]),
                        const SizedBox(height: 4),
                        Text("${r.totalTrips} trips · ★ ${r.rating}", style: const TextStyle(fontSize: 12, color: Colors.black54)),
                      ],
                    ),
                  ),
                  AppComponents.badge(
                    r.status == RiderStatus.active ? "Active" : "Suspended",
                    color: r.status == RiderStatus.active ? AppColors.success : AppColors.danger,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
