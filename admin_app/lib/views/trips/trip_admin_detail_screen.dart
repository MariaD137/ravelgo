import 'package:flutter/material.dart';
import 'package:ravelgo_admin/models/trip_record.dart';
import 'package:ravelgo_admin/services/api_client.dart';
import 'package:ravelgo_admin/theme/app_theme.dart';
import 'package:ravelgo_admin/utils/date_utils.dart';

class TripAdminDetailScreen extends StatefulWidget {
  final TripRecord trip;
  const TripAdminDetailScreen({super.key, required this.trip});

  @override
  State<TripAdminDetailScreen> createState() => _TripAdminDetailScreenState();
}

class _TripAdminDetailScreenState extends State<TripAdminDetailScreen> {
  bool _resolving = false;

  Future<void> _markResolved() async {
    setState(() => _resolving = true);
    try {
      await ApiClient().patch('/trips/${widget.trip.id}/status', body: {'status': 'COMPLETED'});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Trip marked as resolved')),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _resolving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to resolve trip: $e')),
      );
    }
  }

  void _showComingSoon(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$feature: Feature coming soon')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final trip = widget.trip;
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
                _row("Fare", "₦${trip.fare.toStringAsFixed(0)}"),
              ],
            ),
          ),
          const SizedBox(height: 20),
          if (trip.status == TripRecordStatus.disputed) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: AppColors.danger.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
              child: const Text(
                "This trip has been flagged as disputed by the rider (route inconsistent with reported distance).",
                style: TextStyle(fontSize: 13),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: AppComponents.outlineButton(
                    text: "Refund rider",
                    color: AppColors.danger,
                    onPressed: () => _showComingSoon('Refund rider'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AppComponents.primaryButton(
                    text: _resolving ? "Resolving..." : "Mark resolved",
                    onPressed: _resolving ? null : _markResolved,
                  ),
                ),
              ],
            ),
          ] else
            AppComponents.outlineButton(
              text: "Flag this trip for review",
              onPressed: () => _showComingSoon('Flag trip'),
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
          Text(label, style: const TextStyle(color: Colors.black54)),
          Flexible(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600), textAlign: TextAlign.right)),
        ],
      ),
    );
  }
}
