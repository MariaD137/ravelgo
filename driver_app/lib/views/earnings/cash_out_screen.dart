import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ravelgo_driver_app/models/earnings_state.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';

/// Cash out earnings to the linked bank account.
///
/// LOCAL STATE ONLY - NO REAL TRANSFER: the flow validates the amount,
/// confirms, and records a PENDING payout in DriverEarningsState. It never
/// claims money moved; the success screen explicitly says the request is
/// pending until the payments service processes it.
class CashOutScreen extends StatefulWidget {
  const CashOutScreen({super.key});

  @override
  State<CashOutScreen> createState() => _CashOutScreenState();
}

class _CashOutScreenState extends State<CashOutScreen> {
  final _amountController = TextEditingController();
  String? _error;
  bool _submitted = false;

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _cashOut() async {
    final balance = DriverEarningsState.instance.availableBalance;
    final amount = double.tryParse(_amountController.text.replaceAll(',', ''));
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Enter a valid amount');
      return;
    }
    if (amount > balance) {
      setState(() => _error = 'Amount exceeds your available balance');
      return;
    }
    setState(() => _error = null);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm cash out'),
        content: Text('Request a transfer of ₦${amount.toStringAsFixed(0)} to GTBank •••• 1234?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Confirm')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    DriverEarningsState.instance.requestCashOut(amount);
    setState(() => _submitted = true);
  }

  @override
  Widget build(BuildContext context) {
    final balance = DriverEarningsState.instance.availableBalance;
    return Scaffold(
      appBar: AppBar(title: const Text('Cash out')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: _submitted ? _buildResult() : _buildForm(balance),
      ),
    );
  }

  Widget _buildForm(double balance) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: AppComponents.cardDecoration(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Available balance',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
              const SizedBox(height: 4),
              Text('₦${balance.toStringAsFixed(0)}',
                  style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        const SizedBox(height: 20),
        const Text('Amount to cash out'),
        const SizedBox(height: 6),
        TextField(
          controller: _amountController,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(prefixText: '₦ ', hintText: '0', errorText: _error),
        ),
        const SizedBox(height: 16),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.account_balance_outlined, color: AppColors.textSecondary),
          title: const Text('GTBank •••• 1234'),
          subtitle: const Text('Linked payout account',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        ),
        const Spacer(),
        AppComponents.primaryButton(text: 'Request cash out', onPressed: _cashOut),
      ],
    );
  }

  Widget _buildResult() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 40),
        const Icon(Icons.schedule, size: 56, color: AppColors.warning),
        const SizedBox(height: 16),
        const Text('Cash-out request received',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        const Text(
          'Your request is PENDING. Transfers are processed by the payments service, '
          'which is not connected in this build - no money has moved yet. You can track '
          'this request in Payout history.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textSecondary),
        ),
        const Spacer(),
        AppComponents.primaryButton(text: 'Done', onPressed: () => Navigator.pop(context)),
      ],
    );
  }
}
