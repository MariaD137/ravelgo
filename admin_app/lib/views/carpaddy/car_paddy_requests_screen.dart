import 'package:flutter/material.dart';
import 'package:ravelgo_admin/models/admin_actions_state.dart';
import 'package:ravelgo_admin/models/car_paddy_request.dart';
import 'package:ravelgo_admin/theme/app_theme.dart';
import 'package:ravelgo_admin/utils/date_utils.dart';

/// Car Paddy (license renewal) request moderation with working
/// approve/reject. LOCAL STATE ONLY: decisions live in AdminActionsState;
/// persisting them is the API integration point.
class CarPaddyRequestsScreen extends StatefulWidget {
  const CarPaddyRequestsScreen({super.key});

  @override
  State<CarPaddyRequestsScreen> createState() => _CarPaddyRequestsScreenState();
}

class _CarPaddyRequestsScreenState extends State<CarPaddyRequestsScreen> {
  Future<void> _decide(CarPaddyRequest r, CarPaddyStatus status) async {
    final approving = status == CarPaddyStatus.approved;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(approving ? 'Approve request?' : 'Reject request?'),
        content: Text(
            '${approving ? 'Approve' : 'Reject'} the license renewal for ${r.driverName} (${r.plateNumber})?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(approving ? 'Approve' : 'Reject',
                style: TextStyle(color: approving ? AppColors.success : AppColors.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => AdminActionsState.instance.decideCarPaddy(r.id, status));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Request for ${r.driverName} ${approving ? 'approved' : 'rejected'} (recorded locally)'),
    ));
  }

  Color _statusColor(CarPaddyStatus s) {
    switch (s) {
      case CarPaddyStatus.submitted:
        return AppColors.textMuted;
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
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          final r = mockCarPaddyRequests[i];
          final status = AdminActionsState.instance.effectiveCarPaddyStatus(r);
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
                      Text("Submitted ${formatShortDate(r.submittedOn)}", style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                    ],
                  ),
                ),
                if (status == CarPaddyStatus.inReview || status == CarPaddyStatus.submitted)
                  Row(
                    children: [
                      IconButton(
                          tooltip: 'Reject',
                          icon: const Icon(Icons.close, color: AppColors.danger),
                          onPressed: () => _decide(r, CarPaddyStatus.rejected)),
                      IconButton(
                          tooltip: 'Approve',
                          icon: const Icon(Icons.check, color: AppColors.success),
                          onPressed: () => _decide(r, CarPaddyStatus.approved)),
                    ],
                  )
                else
                  AppComponents.badge(_statusLabel(status), color: _statusColor(status)),
              ],
            ),
          );
        },
      ),
    );
  }
}
