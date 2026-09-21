import 'package:flutter/material.dart';
import 'package:ravelgo_admin/config/currency.dart';
import 'package:ravelgo_admin/services/admin_api.dart';
import 'package:ravelgo_admin/services/api_client.dart';
import 'package:ravelgo_admin/theme/app_theme.dart';
import 'package:ravelgo_admin/widgets/reject_reason_dialog.dart';

/// Rental listing detail (AA-1). Takes the RentalListing already loaded by
/// RentalListingsScreen's list call (GET /api/rentals) — every field shown
/// here is already on that model, so no separate detail fetch is needed.
/// The approve/reject actions and confirmation dialog mirror the list
/// screen's own inline buttons exactly (same PATCH /rentals/:id/status).
class RentalListingDetailScreen extends StatefulWidget {
  final RentalListing listing;
  const RentalListingDetailScreen({super.key, required this.listing});

  @override
  State<RentalListingDetailScreen> createState() => _RentalListingDetailScreenState();
}

class _RentalListingDetailScreenState extends State<RentalListingDetailScreen> {
  bool _busy = false;

  Future<void> _setStatus(String status) async {
    final r = widget.listing;
    final approve = status == 'APPROVED';
    String? rejectionReason;
    if (approve) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Approve this listing?'),
          content: Text('${r.vehicle.isEmpty ? 'This vehicle' : r.vehicle} will become visible to riders for rental.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Approve')),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    } else {
      final reason = await showDialog<String>(
        context: context,
        builder: (context) => RejectReasonDialog(itemLabel: r.vehicle.isEmpty ? 'this listing' : r.vehicle),
      );
      if (reason == null || !mounted) return; // cancelled
      rejectionReason = reason;
    }

    setState(() => _busy = true);
    try {
      await AdminApi.setRentalStatus(r.id, status, rejectionReason: rejectionReason);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e is ApiException ? e.message : e.toString())));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Color _statusColor(String s) {
    switch (s) {
      case 'APPROVED':
        return AppColors.success;
      case 'REJECTED':
        return AppColors.danger;
      default:
        return AppColors.warning;
    }
  }

  String _label(String s) => s.isEmpty ? '' : s[0] + s.substring(1).toLowerCase().replaceAll('_', ' ');

  @override
  Widget build(BuildContext context) {
    final r = widget.listing;
    final decided = r.status == 'APPROVED' || r.status == 'REJECTED';
    return Scaffold(
      appBar: AppBar(title: Text(r.vehicle.isEmpty ? 'Rental listing' : r.vehicle)),
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
                    AppComponents.badge(_label(r.status), color: _statusColor(r.status)),
                  ],
                ),
                const Divider(height: 20),
                _row("Vehicle", r.vehicle.isEmpty ? "—" : r.vehicle),
                _row("Owner", r.driverName.isEmpty ? "—" : r.driverName),
                _row("Daily rate", Currency.format(r.dailyRate, decimals: 0)),
                _row("Pickup location", r.location),
                if (r.status == 'REJECTED' && (r.rejectionReason?.isNotEmpty ?? false)) ...[
                  const Divider(height: 20),
                  const Text("Rejection reason", style: TextStyle(color: AppColors.textSecondary)),
                  const SizedBox(height: 4),
                  Text(r.rejectionReason!, style: const TextStyle(color: AppColors.danger)),
                ],
              ],
            ),
          ),
          if (!decided) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _busy ? null : () => _setStatus('APPROVED'),
                    child: const Text('Approve'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
                    onPressed: _busy ? null : () => _setStatus('REJECTED'),
                    child: const Text('Reject'),
                  ),
                ),
              ],
            ),
          ],
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
