import 'package:flutter/material.dart';
import 'package:ravelgo_driver_app/models/earnings_state.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';
import 'package:ravelgo_driver_app/utils/date_utils.dart';

/// Past and pending payouts. LOCAL STATE ONLY: rows come from
/// DriverEarningsState (demo history plus any cash-out requests made this
/// session).
class PayoutHistoryScreen extends StatelessWidget {
  const PayoutHistoryScreen({super.key});

  Color _statusColor(PayoutStatus s) {
    switch (s) {
      case PayoutStatus.paid:
        return AppColors.success;
      case PayoutStatus.pending:
        return AppColors.warning;
      case PayoutStatus.failed:
        return AppColors.danger;
    }
  }

  @override
  Widget build(BuildContext context) {
    final payouts = DriverEarningsState.instance.payouts;
    return Scaffold(
      appBar: AppBar(title: const Text('Payout history')),
      body: payouts.isEmpty
          ? const Center(
              child: Text('No payouts yet', style: TextStyle(color: AppColors.textSecondary)))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: payouts.length,
              separatorBuilder: (_, __) => AppComponents.divider(),
              itemBuilder: (context, i) {
                final p = payouts[i];
                return ListTile(
                  leading: const Icon(Icons.account_balance_outlined, color: AppColors.textSecondary),
                  title: Text('₦${p.amount.toStringAsFixed(0)}',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(formatFriendlyDate(p.date),
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                  trailing: AppComponents.badge(p.status.label, color: _statusColor(p.status)),
                );
              },
            ),
    );
  }
}
