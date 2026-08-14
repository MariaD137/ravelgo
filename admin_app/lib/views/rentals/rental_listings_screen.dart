import 'package:flutter/material.dart';
import 'package:ravelgo_admin/models/rental_listing.dart';
import 'package:ravelgo_admin/theme/app_theme.dart';

class RentalListingsScreen extends StatelessWidget {
  const RentalListingsScreen({super.key});

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
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          final l = mockRentalListings[i];
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
                    AppComponents.badge(_statusLabel(l.status), color: _statusColor(l.status)),
                  ],
                ),
                const SizedBox(height: 6),
                Text("Owner: ${l.ownerName} · ${l.location}", style: const TextStyle(fontSize: 12, color: Colors.black54)),
                const SizedBox(height: 6),
                Text("₦${l.dailyRate.toStringAsFixed(0)} / day", style: const TextStyle(fontWeight: FontWeight.w700)),
                if (l.status == RentalListingStatus.pendingApproval) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(child: AppComponents.outlineButton(text: "Reject", color: AppColors.danger, onPressed: () {})),
                      const SizedBox(width: 10),
                      Expanded(child: AppComponents.primaryButton(text: "Approve", onPressed: () {})),
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
