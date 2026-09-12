import 'package:flutter/material.dart';
import 'package:ravelgo_user_app/config/currency.dart';
import 'package:ravelgo_user_app/services/api_client.dart';
import 'package:ravelgo_user_app/services/wallet_api.dart';
import 'package:ravelgo_user_app/theme/app_theme.dart';

/// Full RavelGo Cash transaction history — GET /api/wallet/transactions
/// already returns up to 50, newest first; PaymentView's wallet card only
/// shows the latest 5 inline, this screen is the "View all" destination.
class WalletHistoryScreen extends StatefulWidget {
  const WalletHistoryScreen({super.key});

  @override
  State<WalletHistoryScreen> createState() => _WalletHistoryScreenState();
}

class _WalletHistoryScreenState extends State<WalletHistoryScreen> {
  List<WalletTransaction>? _txns;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final txns = await WalletApi.transactions();
      if (!mounted) return;
      setState(() => _txns = txns);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e is ApiException ? e.message : e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        leading: const BackButton(color: AppColors.textPrimary),
        backgroundColor: AppColors.surface,
        elevation: 0,
        centerTitle: true,
        title: const Text('Wallet history', style: TextStyle(color: AppColors.textPrimary)),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return ListView(
        children: [
          const SizedBox(height: 80),
          Icon(Icons.error_outline, size: 40, color: AppColors.error.withValues(alpha: 0.7)),
          const SizedBox(height: 12),
          Center(child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSecondary))),
          const SizedBox(height: 12),
          Center(child: TextButton(onPressed: _load, child: const Text('Retry'))),
        ],
      );
    }
    final txns = _txns;
    if (txns == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (txns.isEmpty) {
      return ListView(
        children: const [
          SizedBox(height: 100),
          Icon(Icons.receipt_long_outlined, size: 40, color: AppColors.textSecondary),
          SizedBox(height: 12),
          Center(child: Text('No wallet activity yet.', style: TextStyle(color: AppColors.textSecondary))),
        ],
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: txns.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) => _txnTile(txns[i]),
    );
  }

  Widget _txnTile(WalletTransaction t) {
    final isCredit = t.amount >= 0;
    final statusColor = switch (t.status.toUpperCase()) {
      'COMPLETED' => AppColors.success,
      'FAILED' => AppColors.error,
      _ => AppColors.warning, // PENDING or any future status
    };
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: AppColors.surfaceElevated,
        child: Icon(_iconFor(t.type), color: AppColors.textPrimary, size: 20),
      ),
      title: Text(_prettyLabel(t.type)),
      subtitle: Text(
        '${_formatDate(t.createdAt)} · ${t.status[0]}${t.status.substring(1).toLowerCase()}',
        style: TextStyle(color: statusColor, fontSize: 12.5),
      ),
      trailing: Text(
        '${isCredit ? '+' : ''}${Currency.format(t.amount)}',
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: isCredit ? AppColors.success : AppColors.textPrimary,
        ),
      ),
    );
  }

  IconData _iconFor(String type) => switch (type.toUpperCase()) {
        'TOPUP' => Icons.add_circle_outline,
        'REFUND' => Icons.replay_circle_filled_outlined,
        'RIDE_PAYMENT' => Icons.directions_car_outlined,
        'RENTAL_PAYMENT' => Icons.key_outlined,
        'DELIVERY_PAYMENT' => Icons.local_shipping_outlined,
        _ => Icons.account_balance_wallet_outlined,
      };

  String _prettyLabel(String type) {
    final words = type.split('_').where((w) => w.isNotEmpty);
    return words.map((w) => w[0] + w.substring(1).toLowerCase()).join(' ');
  }

  String _formatDate(DateTime d) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final ampm = d.hour < 12 ? 'AM' : 'PM';
    return '${months[d.month - 1]} ${d.day}, $h:${d.minute.toString().padLeft(2, '0')} $ampm';
  }
}
