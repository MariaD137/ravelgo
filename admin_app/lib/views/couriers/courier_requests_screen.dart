import 'package:flutter/material.dart';
import 'package:ravelgo_admin/models/courier_request.dart';
import 'package:ravelgo_admin/theme/app_theme.dart';

class CourierRequestsScreen extends StatelessWidget {
  const CourierRequestsScreen({super.key});

  Color _statusColor(CourierRequestStatus s) {
    switch (s) {
      case CourierRequestStatus.awaitingCourier:
        return AppColors.warning;
      case CourierRequestStatus.inTransit:
        return AppColors.info;
      case CourierRequestStatus.delivered:
        return AppColors.success;
      case CourierRequestStatus.cancelled:
        return AppColors.textMuted;
    }
  }

  String _statusLabel(CourierRequestStatus s) {
    switch (s) {
      case CourierRequestStatus.awaitingCourier:
        return "Awaiting courier";
      case CourierRequestStatus.inTransit:
        return "In transit";
      case CourierRequestStatus.delivered:
        return "Delivered";
      case CourierRequestStatus.cancelled:
        return "Cancelled";
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Be a Courier — Requests")),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
            child: const Text(
              "Couriers are Riders using the Be a Courier feature. RavelGo charges a fixed fee per request, separate from the courier's negotiated fare.",
              style: TextStyle(fontSize: 12.5),
            ),
          ),
          ...mockCourierRequests.map((c) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: AppComponents.cardDecoration(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(c.id, style: const TextStyle(fontWeight: FontWeight.w700)),
                          AppComponents.badge(_statusLabel(c.status), color: _statusColor(c.status)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text("${c.pickupStation} → ${c.dropoffStation}", style: const TextStyle(fontSize: 13)),
                      const SizedBox(height: 6),
                      Text("Requested by ${c.requesterName}${c.courierName != null ? ' · Courier: ${c.courierName}' : ''}",
                          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text("RavelGo fee: ₦${c.fixedFee.toStringAsFixed(0)}", style: const TextStyle(fontSize: 12)),
                          Text("Courier fare: ₦${c.courierFare.toStringAsFixed(0)}", style: const TextStyle(fontWeight: FontWeight.w600)),
                        ],
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
