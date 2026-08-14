import 'package:flutter/material.dart';
import 'package:ravelgo_admin/models/car_paddy_request.dart';
import 'package:ravelgo_admin/theme/app_theme.dart';
import 'package:ravelgo_admin/utils/date_utils.dart';

class CarPaddyRequestsScreen extends StatelessWidget {
  const CarPaddyRequestsScreen({super.key});

  Color _statusColor(CarPaddyStatus s) {
    switch (s) {
      case CarPaddyStatus.submitted:
        return Colors.grey;
      case CarPaddyStatus.inReview:
        return AppColors.warning;
      case CarPaddyStatus.approved:
        return AppColors.success;
      case CarPaddyStatus.rejected:
        return AppColors.danger;
    }
  }

  String _statusLabel(CarPaddyStatus s) {
    switch (s) {
      case CarPaddyStatus.submitted:
        return "Submitted";
      case CarPaddyStatus.inReview:
        return "In review";
      case CarPaddyStatus.approved:
        return "Approved";
      case CarPaddyStatus.rejected:
        return "Rejected";
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Car Paddy Requests")),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: mockCarPaddyRequests.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          final r = mockCarPaddyRequests[i];
          return Container(
            padding: const EdgeInsets.all(14),
            decoration: AppComponents.cardDecoration(),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("${r.driverName} · ${r.plateNumber}", style: const TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text("Submitted ${formatShortDate(r.submittedOn)}", style: const TextStyle(fontSize: 12, color: Colors.black54)),
                    ],
                  ),
                ),
                if (r.status == CarPaddyStatus.inReview || r.status == CarPaddyStatus.submitted)
                  Row(
                    children: [
                      IconButton(icon: const Icon(Icons.close, color: AppColors.danger), onPressed: () {}),
                      IconButton(icon: const Icon(Icons.check, color: AppColors.success), onPressed: () {}),
                    ],
                  )
                else
                  AppComponents.badge(_statusLabel(r.status), color: _statusColor(r.status)),
              ],
            ),
          );
        },
      ),
    );
  }
}
