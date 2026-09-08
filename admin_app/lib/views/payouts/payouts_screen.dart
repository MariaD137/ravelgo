import 'package:flutter/material.dart';
import 'package:ravelgo_admin/config/currency.dart';
import 'package:ravelgo_admin/services/admin_api.dart';
import 'package:ravelgo_admin/services/api_client.dart';
import 'package:ravelgo_admin/theme/app_theme.dart';
import 'package:ravelgo_admin/utils/date_utils.dart';
import 'package:ravelgo_admin/views/payouts/create_payout_screen.dart';

/// Driver payouts admin screen (GET/POST /api/payouts...). Covers the full
/// PENDING -> PROCESSING -> COMPLETED/FAILED lifecycle the backend exposes.
class PayoutsScreen extends StatefulWidget {
  const PayoutsScreen({super.key});

  @override
  State<PayoutsScreen> createState() => _PayoutsScreenState();
}

const _statusFilters = ['ALL', 'PENDING', 'PROCESSING', 'COMPLETED', 'FAILED', 'CANCELLED'];

class _PayoutsScreenState extends State<PayoutsScreen> {
  bool _loading = true;
  bool _busy = false;
  String? _error;
  List<AdminPayout> _payouts = const [];
  String _filter = 'ALL';

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
      final payouts = await AdminApi.payouts(status: _filter == 'ALL' ? null : _filter);
      if (!mounted) return;
      setState(() {
        _payouts = payouts;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException && e.statusCode == 403
            ? 'Sign in as an admin to manage payouts.'
            : e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _process(AdminPayout p) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Process this payout?'),
        content: Text('${p.driverName.isEmpty ? p.driverEmail : p.driverName} · ${Currency.format(p.amount, decimals: 0)} for ${p.period}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Process')),
        ],
      ),
    );
    if (confirmed != true) return;
    await _run(() => AdminApi.processPayout(p.id), success: 'Payout is processing');
  }

  Future<void> _complete(AdminPayout p) async {
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Mark payout completed?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${p.driverName.isEmpty ? p.driverEmail : p.driverName} · ${Currency.format(p.amount, decimals: 0)}'),
              const SizedBox(height: 8),
              const Text(
                'Enter the real bank/wire transfer reference for the transfer you just made outside RavelGo. This cannot be left blank or made up — it is the only record that the transfer actually happened.',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                decoration: const InputDecoration(labelText: 'Transaction ID (required)', border: OutlineInputBorder()),
                onChanged: (_) => setDialogState(() {}),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.success),
              onPressed: controller.text.trim().length < 4 ? null : () => Navigator.pop(context, true),
              child: const Text('Mark completed'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    await _run(() => AdminApi.completePayout(p.id, transactionId: controller.text.trim()), success: 'Payout marked completed');
  }

  Future<void> _fail(AdminPayout p) async {
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Mark payout failed?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${p.driverName.isEmpty ? p.driverEmail : p.driverName} · ${Currency.format(p.amount, decimals: 0)}'),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                decoration: const InputDecoration(labelText: 'Failure reason (required)', border: OutlineInputBorder()),
                onChanged: (_) => setDialogState(() {}),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
              onPressed: controller.text.trim().isEmpty ? null : () => Navigator.pop(context, true),
              child: const Text('Mark failed'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    await _run(() => AdminApi.failPayout(p.id, controller.text.trim()), success: 'Payout marked failed');
  }

  Future<void> _run(Future<void> Function() action, {required String success}) async {
    setState(() => _busy = true);
    try {
      await action();
      await _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(success)));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e is ApiException ? e.message : e.toString())));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Color _color(String s) {
    switch (s) {
      case 'COMPLETED':
        return AppColors.success;
      case 'FAILED':
      case 'CANCELLED':
        return AppColors.danger;
      case 'PROCESSING':
        return AppColors.info;
      default:
        return AppColors.warning;
    }
  }

  String _label(String s) => s.isEmpty ? '' : s[0] + s.substring(1).toLowerCase().replaceAll('_', ' ');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Payouts"),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () async {
              final created = await Navigator.push<bool>(
                  context, MaterialPageRoute(builder: (_) => const CreatePayoutScreen()));
              if (created == true) _load();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          SizedBox(
            height: 48,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              itemCount: _statusFilters.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final f = _statusFilters[i];
                final selected = f == _filter;
                return ChoiceChip(
                  label: Text(f == 'ALL' ? 'All' : _label(f)),
                  selected: selected,
                  onSelected: (_) {
                    setState(() => _filter = f);
                    _load();
                  },
                );
              },
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : (_error != null ? _err() : _list()),
          ),
        ],
      ),
    );
  }

  Widget _err() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.danger)),
            TextButton(onPressed: _load, child: const Text('Try again')),
          ]),
        ),
      );

  Widget _list() {
    if (_payouts.isEmpty) {
      return const Center(child: Text("No payouts yet.", style: TextStyle(color: AppColors.textSecondary)));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _payouts.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          final p = _payouts[i];
          return Container(
            padding: const EdgeInsets.all(14),
            decoration: AppComponents.cardDecoration(),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p.driverName.isEmpty ? p.driverEmail : p.driverName,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text("Period ${p.period} · ${formatFriendlyDate(p.createdAt)}",
                          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                      if (p.status == 'FAILED' && p.failureReason != null) ...[
                        const SizedBox(height: 2),
                        Text(p.failureReason!,
                            maxLines: 2, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11, color: AppColors.danger)),
                      ],
                      if (p.transactionId != null) ...[
                        const SizedBox(height: 2),
                        Text("Ref: ${p.transactionId}",
                            style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                      ],
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    AppComponents.badge(_label(p.status), color: _color(p.status)),
                    const SizedBox(height: 6),
                    Text(Currency.format(p.amount, decimals: 0), style: const TextStyle(fontWeight: FontWeight.w700)),
                  ],
                ),
                if (p.status == 'PENDING' || p.status == 'PROCESSING')
                  PopupMenuButton<String>(
                    enabled: !_busy,
                    onSelected: (v) {
                      if (v == 'process') _process(p);
                      if (v == 'complete') _complete(p);
                      if (v == 'fail') _fail(p);
                    },
                    itemBuilder: (_) => [
                      if (p.status == 'PENDING') const PopupMenuItem(value: 'process', child: Text('Process')),
                      if (p.status == 'PROCESSING') const PopupMenuItem(value: 'complete', child: Text('Mark completed')),
                      const PopupMenuItem(value: 'fail', child: Text('Mark failed')),
                    ],
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
