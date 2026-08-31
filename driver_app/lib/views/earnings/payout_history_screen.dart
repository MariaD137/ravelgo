import 'package:flutter/material.dart';
import 'package:ravelgo_driver_app/services/api_client.dart';
import 'package:ravelgo_driver_app/services/driver_api.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';
import 'package:ravelgo_driver_app/utils/date_utils.dart';

/// Past and pending payouts from the backend (GET /api/payouts/history).
class PayoutHistoryScreen extends StatefulWidget {
  const PayoutHistoryScreen({super.key});

  @override
  State<PayoutHistoryScreen> createState() => _PayoutHistoryScreenState();
}

class _PayoutHistoryScreenState extends State<PayoutHistoryScreen> {
  bool _loading = true;
  String? _error;
  List<Payout> _payouts = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final payouts = await DriverApi.payoutHistory();
      if (!mounted) return;
      setState(() {
        _payouts = payouts;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException && e.statusCode == 403
            ? 'Your account isn\'t set up as a driver yet.'
            : e.toString();
        _loading = false;
      });
    }
  }

  Color _statusColor(String s) {
    switch (s) {
      case 'COMPLETED':
        return AppColors.success;
      case 'PENDING':
      case 'PROCESSING':
        return AppColors.warning;
      case 'FAILED':
      case 'CANCELLED':
        return AppColors.danger;
      default:
        return AppColors.textSecondary;
    }
  }

  String _pretty(String s) => s.isEmpty ? '' : s[0] + s.substring(1).toLowerCase().replaceAll('_', ' ');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Payout history')),
      body: _body(),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.danger)),
              TextButton(onPressed: _load, child: const Text('Try again')),
            ],
          ),
        ),
      );
    }
    if (_payouts.isEmpty) {
      return const Center(child: Text('No payouts yet', style: TextStyle(color: AppColors.textSecondary)));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _payouts.length,
        separatorBuilder: (_, __) => AppComponents.divider(),
        itemBuilder: (context, i) {
          final p = _payouts[i];
          return ListTile(
            leading: const Icon(Icons.account_balance_outlined, color: AppColors.textSecondary),
            title: Text('\$${p.amount.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(
              [if (p.period.isNotEmpty) p.period, formatFriendlyDate(p.createdAt)].join(' · '),
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
            trailing: AppComponents.badge(_pretty(p.status), color: _statusColor(p.status)),
          );
        },
      ),
    );
  }
}
