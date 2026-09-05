import 'package:flutter/material.dart';
import 'package:ravelgo_admin/config/currency.dart';
import 'package:ravelgo_admin/services/admin_api.dart';
import 'package:ravelgo_admin/theme/app_theme.dart';
import 'package:ravelgo_admin/utils/date_utils.dart';

/// Real trip detail. Shows only what the backend actually returns for an
/// Admin caller (GET /api/trips, /api/trips/:id) — no refund/dispute actions,
/// since no payment-adjustment or dispute-resolution endpoint exists yet.
/// Advancing a trip's own status is already covered by the driver/backend
/// state machine (services/trip-status.ts) and isn't duplicated here.
class TripAdminDetailScreen extends StatelessWidget {
  final AdminTrip trip;
  const TripAdminDetailScreen({super.key, required this.trip});

  Color _statusColor(String s) {
    switch (s) {
      case 'IN_PROGRESS':
      case 'MATCHED':
        return AppColors.info;
      case 'COMPLETED':
        return AppColors.success;
      case 'DISPUTED':
        return AppColors.danger;
      default:
        return AppColors.textMuted;
    }
  }

  String _label(String s) => s.isEmpty ? '' : s[0] + s.substring(1).toLowerCase().replaceAll('_', ' ');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Trip ${trip.id.length > 8 ? trip.id.substring(0, 8) : trip.id}')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: AppComponents.cardDecoration(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("Status", style: TextStyle(color: AppColors.textSecondary)),
                    AppComponents.badge(_label(trip.status), color: _statusColor(trip.status)),
                  ],
                ),
                const Divider(height: 20),
                _row("Rider", trip.riderName.isEmpty ? "—" : trip.riderName),
                _row("Driver", trip.driverName ?? "Unassigned"),
                _row("Pickup", trip.pickup),
                _row("Destination", trip.destination),
                _row("Requested", formatFriendlyDate(trip.requestedAt)),
                _row("Fare", Currency.format(trip.fare, decimals: 0)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: AppComponents.cardDecoration(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Payment", style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                if (trip.paymentStatus == null)
                  const Text("Not charged yet.", style: TextStyle(color: AppColors.textSecondary, fontSize: 13))
                else ...[
                  _row("Status", _label(trip.paymentStatus!)),
                  _row("Method", trip.paymentMethod ?? "—"),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: AppColors.textSecondary)),
          Flexible(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600), textAlign: TextAlign.right)),
        ],
      ),
    );
  }
}
