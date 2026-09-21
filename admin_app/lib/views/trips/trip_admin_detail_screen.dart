import 'package:flutter/material.dart';
import 'package:ravelgo_admin/config/currency.dart';
import 'package:ravelgo_admin/services/admin_api.dart';
import 'package:ravelgo_admin/services/api_client.dart';
import 'package:ravelgo_admin/theme/app_theme.dart';
import 'package:ravelgo_admin/utils/date_utils.dart';

/// Real trip detail. Shows only what the backend actually returns for an
/// Admin caller (GET /api/trips, /api/trips/:id).
///
/// Refunds (A-3 / B-6): POST /api/trips/:id/refund has always done the real
/// work — return CARD funds through Paystack, credit a WALLET balance,
/// reverse the commission split on the ledger, and write an audit row — but
/// nothing in this app could call it, so issuing one meant going into the
/// database and Paystack by hand. The action below is that endpoint and
/// nothing more: the backend still decides whether this admin may refund
/// (requireAdminPermission "payouts:write") and how much, and a refusal is
/// shown as it comes back.
///
/// Advancing a trip's own status stays with the driver/backend state machine
/// (services/trip-status.ts) and is not duplicated here.
class TripAdminDetailScreen extends StatefulWidget {
  final AdminTrip trip;
  const TripAdminDetailScreen({super.key, required this.trip});

  @override
  State<TripAdminDetailScreen> createState() => _TripAdminDetailScreenState();
}

class _TripAdminDetailScreenState extends State<TripAdminDetailScreen> {
  AdminTrip get trip => widget.trip;

  bool _busy = false;
  // Set once a refund succeeds in this session: the screen was handed a trip
  // object by the list that opened it, so it cannot re-read the payment row,
  // and must not keep offering to refund what it just refunded.
  double? _refunded;

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

  String _label(String s) =>
      s.isEmpty ? '' : s[0] + s.substring(1).toLowerCase().replaceAll('_', ' ');

  Future<void> _refund() async {
    if (_busy) return;
    final charged = trip.paymentAmount ?? trip.fare;
    final result = await showDialog<_RefundRequest>(
      context: context,
      builder: (_) => _RefundDialog(charged: charged, method: trip.paymentMethod),
    );
    if (result == null || !mounted) return;

    setState(() => _busy = true);
    try {
      final refunded = await AdminApi.refundTrip(
        trip.id,
        reason: result.reason,
        amount: result.amount,
      );
      if (!mounted) return;
      setState(() {
        _refunded = refunded;
        _busy = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Refunded ${Currency.format(refunded, decimals: 0)}.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(describeApiFailure(e, what: 'this refund'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: Text('Trip ${trip.id.length > 8 ? trip.id.substring(0, 8) : trip.id}')),
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
                  const Text("Not charged yet.",
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 13))
                else ...[
                  _row("Status",
                      _refunded != null ? "Refunded" : _label(trip.paymentStatus!)),
                  _row("Method", trip.paymentMethod ?? "—"),
                  if (trip.paymentAmount != null)
                    _row("Charged", Currency.format(trip.paymentAmount!, decimals: 0)),
                  if (_refunded != null)
                    _row("Refunded", Currency.format(_refunded!, decimals: 0)),
                  const SizedBox(height: 12),
                  if (trip.isRefundable && _refunded == null)
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : _refund,
                        icon: _busy
                            ? const SizedBox(
                                height: 16,
                                width: 16,
                                child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.undo_outlined, size: 18),
                        label: Text(_busy ? 'Refunding…' : 'Issue refund'),
                      ),
                    )
                  else if (!trip.isRefundable && _refunded == null)
                    const Text(
                      'Only a settled payment can be refunded.',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                    ),
                  if (trip.paymentMethod == 'CASH')
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'Cash never passed through RavelGo: a refund here reverses the '
                        'commission on the ledger only. Returning the cash itself happens '
                        'between rider and driver.',
                        style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                      ),
                    ),
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
          Flexible(
              child: Text(value,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                  textAlign: TextAlign.right)),
        ],
      ),
    );
  }
}

/// What the admin confirmed: a reason (the backend requires one, and it lands
/// in the audit log) and an optional partial amount.
class _RefundRequest {
  final String reason;
  final double? amount;
  const _RefundRequest(this.reason, this.amount);
}

/// Refunds move real money and reverse a commission split, so nothing happens
/// on a single tap: the amount and the reason are both confirmed here first.
class _RefundDialog extends StatefulWidget {
  const _RefundDialog({required this.charged, this.method});
  final double charged;
  final String? method;

  @override
  State<_RefundDialog> createState() => _RefundDialogState();
}

class _RefundDialogState extends State<_RefundDialog> {
  final _formKey = GlobalKey<FormState>();
  final _reason = TextEditingController();
  final _amount = TextEditingController();
  bool _partial = false;

  @override
  void dispose() {
    _reason.dispose();
    _amount.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(_RefundRequest(
      _reason.text.trim(),
      _partial ? double.parse(_amount.text.trim()) : null,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Issue refund'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Charged ${Currency.format(widget.charged, decimals: 0)}'
              '${widget.method != null ? ' by ${widget.method!.toLowerCase()}' : ''}.',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _reason,
              decoration: const InputDecoration(
                labelText: 'Reason',
                hintText: 'Recorded in the audit log',
              ),
              maxLength: 500,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'A reason is required' : null,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Partial refund', style: TextStyle(fontSize: 14)),
              value: _partial,
              onChanged: (v) => setState(() => _partial = v),
            ),
            if (_partial)
              TextFormField(
                controller: _amount,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Amount'),
                validator: (v) {
                  final parsed = double.tryParse((v ?? '').trim());
                  if (parsed == null) return 'Enter an amount';
                  if (parsed <= 0) return 'Amount must be more than zero';
                  // The backend rejects this too (400) — catching it here
                  // saves a round trip, it does not replace that check.
                  if (parsed > widget.charged) {
                    return 'Cannot exceed ${Currency.format(widget.charged, decimals: 0)}';
                  }
                  return null;
                },
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: const Text('Refund')),
      ],
    );
  }
}
