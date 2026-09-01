import 'package:flutter/material.dart';
import 'package:ravelgo_admin/config/currency.dart';
import 'package:ravelgo_admin/models/admin_actions_state.dart';
import 'package:ravelgo_admin/models/trip_record.dart';
import 'package:ravelgo_admin/theme/app_theme.dart';
import 'package:ravelgo_admin/utils/date_utils.dart';

/// Admin trip detail with working refund / flag / resolve actions.
/// LOCAL STATE ONLY: decisions are recorded in AdminActionsState and the UI
/// updates; no payment backend exists, so a refund is recorded as REQUESTED
/// (never claimed processed) - executing it is the payments integration
/// point.
class TripAdminDetailScreen extends StatefulWidget {
  final TripRecord trip;
  const TripAdminDetailScreen({super.key, required this.trip});

  @override
  State<TripAdminDetailScreen> createState() => _TripAdminDetailScreenState();
}

class _TripAdminDetailScreenState extends State<TripAdminDetailScreen> {
  AdminActionsState get _state => AdminActionsState.instance;
  TripRecord get trip => widget.trip;

  bool get _refundRequested => _state.refundRequestedTrips.contains(trip.id);
  bool get _flagged =>
      trip.status == TripRecordStatus.disputed || _state.flaggedTrips.contains(trip.id);
  bool get _resolved => _state.resolvedTrips.contains(trip.id);

  Future<void> _refundRider() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Refund rider?'),
        content: Text(
            'Record a refund of ${Currency.format(trip.fare, decimals: 0)} to ${trip.riderName} for trip ${trip.id}? '
            'The refund is queued as REQUESTED - money moves only when the payments service processes it.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Request refund', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _state.requestRefund(trip.id));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Refund recorded as REQUESTED (payments service not connected - not yet processed)'),
    ));
  }

  Future<void> _flagTrip() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Flag this trip?'),
        content: Text('Mark trip ${trip.id} for review by the operations team?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Flag trip')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _state.flagTrip(trip.id));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Trip flagged for review')),
    );
  }

  void _markResolved() {
    setState(() => _state.resolveTrip(trip.id));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Dispute marked resolved')),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(trip.id)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: AppComponents.cardDecoration(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _row("Rider", trip.riderName),
                _row("Driver", trip.driverName),
                _row("Pickup", trip.pickup),
                _row("Destination", trip.destination),
                _row("Date", formatFriendlyDate(trip.date)),
                _row("Fare", Currency.format(trip.fare, decimals: 0)),
              ],
            ),
          ),
          const SizedBox(height: 20),
          if (_refundRequested)
            Container(
              padding: const EdgeInsets.all(14),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12)),
              child: const Text(
                'Refund REQUESTED - awaiting processing by the payments service.',
                style: TextStyle(fontSize: 13),
              ),
            ),
          if (_flagged && !_resolved) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                  color: AppColors.danger.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12)),
              child: Text(
                trip.status == TripRecordStatus.disputed
                    ? "This trip has been flagged as disputed by the rider (route inconsistent with reported distance)."
                    : "This trip has been flagged for review by an administrator.",
                style: const TextStyle(fontSize: 13),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: AppComponents.outlineButton(
                    text: _refundRequested ? "Refund requested" : "Refund rider",
                    color: AppColors.danger,
                    onPressed: _refundRequested ? null : _refundRider,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: AppComponents.primaryButton(text: "Mark resolved", onPressed: _markResolved)),
              ],
            ),
          ] else if (_resolved)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12)),
              child: const Text('Dispute resolved.', style: TextStyle(fontSize: 13)),
            )
          else
            AppComponents.outlineButton(text: "Flag this trip for review", onPressed: _flagTrip),
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
