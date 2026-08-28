import 'package:flutter/material.dart';
import 'package:ravelgo_admin/models/admin_actions_state.dart';
import 'package:ravelgo_admin/models/rental_listing.dart';
import 'package:ravelgo_admin/theme/app_theme.dart';

/// Rental listing moderation with working approve/reject.
/// LOCAL STATE ONLY: decisions are recorded in AdminActionsState (the badge
/// updates immediately); persisting them is the listings-API integration
/// point.
class RentalListingsScreen extends StatefulWidget {
  const RentalListingsScreen({super.key});

  @override
  State<RentalListingsScreen> createState() => _RentalListingsScreenState();
}

class _RentalListingsScreenState extends State<RentalListingsScreen> {
  Future<void> _decide(RentalListing l, RentalListingStatus status) async {
    final approving = status == RentalListingStatus.approved;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(approving ? 'Approve listing?' : 'Reject listing?'),
        content: Text(
            '${approving ? 'Approve' : 'Reject'} ${l.vehicle} (${l.id}) by ${l.ownerName}?'),
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
    setState(() => AdminActionsState.instance.decideRental(l.id, status));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Listing ${l.id} ${approving ? 'approved' : 'rejected'} (recorded locally)'),
    ));
  }

  Color _statusColor(RentalListingStatus s) {
    switch (s) {
      case RentalListingStatus.pendingApproval:
        return AppColors.warning;
      case RentalListingStatus.approved:
        return AppColors.success;
      case RentalListingStatus.rejected:
        return AppColors.danger;
    }
  }

  String _statusLabel(RentalListingStatus s) {
    switch (s) {
      case RentalListingStatus.pendingApproval:
        return "Pending approval";
      case RentalListingStatus.approved:
        return "Approved";
      case RentalListingStatus.rejected:
        return "Rejected";
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Luxury Car Rental Listings")),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: mockRentalListings.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          final l = mockRentalListings[i];
          final status = AdminActionsState.instance.effectiveRentalStatus(l);
          return Container(
            padding: const EdgeInsets.all(14),
            decoration: AppComponents.cardDecoration(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(child: Text(l.vehicle, style: const TextStyle(fontWeight: FontWeight.w600))),
                    AppComponents.badge(_statusLabel(status), color: _statusColor(status)),
                  ],
                ),
                const SizedBox(height: 6),
                Text("Owner: ${l.ownerName} · ${l.location}", style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                const SizedBox(height: 6),
                Text("₦${l.dailyRate.toStringAsFixed(0)} / day", style: const TextStyle(fontWeight: FontWeight.w700)),
                if (status == RentalListingStatus.pendingApproval) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                          child: AppComponents.outlineButton(
                              text: "Reject",
                              color: AppColors.danger,
                              onPressed: () => _decide(l, RentalListingStatus.rejected))),
                      const SizedBox(width: 10),
                      Expanded(
                          child: AppComponents.primaryButton(
                              text: "Approve",
                              onPressed: () => _decide(l, RentalListingStatus.approved))),
                    ],
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}
