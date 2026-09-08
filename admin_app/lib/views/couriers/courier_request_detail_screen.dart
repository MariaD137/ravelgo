import 'package:flutter/material.dart';
import 'package:ravelgo_admin/config/currency.dart';
import 'package:ravelgo_admin/services/admin_api.dart';
import 'package:ravelgo_admin/services/api_client.dart';
import 'package:ravelgo_admin/theme/app_theme.dart';
import 'package:ravelgo_admin/utils/date_utils.dart';

/// Delivery detail (AA-1). Takes the CourierRequest already loaded by
/// CourierRequestsScreen's list call (GET /api/courier-requests) — every
/// field shown here is already on that model, so no separate detail fetch is
/// needed. Status actions call the same PATCH /courier-requests/:id/status
/// the list screen's inline buttons use; on success this pops back to the
/// list so it can reload and show the new status.
class CourierRequestDetailScreen extends StatefulWidget {
  final CourierRequest request;
  const CourierRequestDetailScreen({super.key, required this.request});

  @override
  State<CourierRequestDetailScreen> createState() => _CourierRequestDetailScreenState();
}

class _CourierRequestDetailScreenState extends State<CourierRequestDetailScreen> {
  bool _busy = false;

  Future<void> _setStatus(String status) async {
    setState(() => _busy = true);
    try {
      await AdminApi.setCourierStatus(widget.request.id, status);
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
      case 'DELIVERED':
        return AppColors.success;
      case 'CANCELLED':
        return AppColors.danger;
      case 'IN_TRANSIT':
      case 'PICKED_UP':
      case 'MATCHED':
        return AppColors.info;
      default:
        return AppColors.warning;
    }
  }

  String _label(String s) => s.isEmpty ? '' : s[0] + s.substring(1).toLowerCase().replaceAll('_', ' ');

  @override
  Widget build(BuildContext context) {
    final c = widget.request;
    final done = c.status == 'DELIVERED' || c.status == 'CANCELLED';
    return Scaffold(
      appBar: AppBar(title: Text('Delivery ${c.id.length > 8 ? c.id.substring(0, 8) : c.id}')),
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
                    AppComponents.badge(_label(c.status), color: _statusColor(c.status)),
                  ],
                ),
                const Divider(height: 20),
                _row("Pickup", c.pickupAddress),
                _row("Dropoff", c.dropoffAddress),
                _row("Package", c.packageDescription),
                _row("Recipient", c.recipientName),
                _row("Sender", c.senderName.isEmpty ? "—" : c.senderName),
                _row("Driver", c.driverName ?? "Unassigned"),
                _row("Requested", formatFriendlyDate(c.requestedAt)),
                _row("Fare", Currency.format(c.fare, decimals: 0)),
              ],
            ),
          ),
          if (!done) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                if (c.status != 'IN_TRANSIT') ...[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _busy ? null : () => _setStatus('IN_TRANSIT'),
                      child: const Text('Mark in transit'),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                // No "Delivered" action here — the backend requires a
                // delivery photo and the recipient's signature to mark a
                // request DELIVERED, which only the driver app captures.
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
                    onPressed: _busy ? null : () => _setStatus('CANCELLED'),
                    child: const Text('Cancel delivery'),
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
