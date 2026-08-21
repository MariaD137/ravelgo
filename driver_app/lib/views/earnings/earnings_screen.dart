import 'package:flutter/material.dart';
import 'package:ravelgo_driver_app/services/api_client.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';

class EarningsScreen extends StatefulWidget {
  final bool embedded;
  const EarningsScreen({super.key, this.embedded = false});

  @override
  State<EarningsScreen> createState() => _EarningsScreenState();
}

class _EarningsScreenState extends State<EarningsScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _payouts = [];
  double _totalEarnings = 0;
  int _totalPayouts = 0;

  @override
  void initState() {
    super.initState();
    _loadEarnings();
  }

  Future<void> _loadEarnings() async {
    try {
      final response = await ApiClient().get('/payouts/history');
      if (!mounted) return;

      List<dynamic> payoutList;
      int total = 0;
      if (response is Map) {
        payoutList = response['data'] is List ? response['data'] : [];
        total = response['total'] ?? payoutList.length;
      } else if (response is List) {
        payoutList = response;
        total = payoutList.length;
      } else {
        payoutList = [];
      }

      double earnings = 0;
      final parsed = <Map<String, dynamic>>[];
      for (final p in payoutList) {
        final payout = Map<String, dynamic>.from(p);
        parsed.add(payout);
        final amount = (payout['amount'] ?? 0).toDouble();
        if (payout['status'] == 'COMPLETED') {
          earnings += amount;
        }
      }

      setState(() {
        _payouts = parsed;
        _totalEarnings = earnings;
        _totalPayouts = total;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  String _formatAmount(double amount) {
    return "₦${amount.toStringAsFixed(0)}";
  }

  String _statusLabel(String? status) {
    switch (status) {
      case 'COMPLETED':
        return 'Completed';
      case 'PENDING':
        return 'Pending';
      case 'PROCESSING':
        return 'Processing';
      case 'FAILED':
        return 'Failed';
      default:
        return status ?? 'Unknown';
    }
  }

  Color _statusColor(String? status) {
    switch (status) {
      case 'COMPLETED':
        return AppColors.success;
      case 'PENDING':
        return AppColors.primaryDark;
      case 'PROCESSING':
        return Colors.blue;
      case 'FAILED':
        return AppColors.danger;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = SafeArea(
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Failed to load earnings', style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        Text(_error!, style: const TextStyle(fontSize: 12, color: Colors.black54), textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        AppComponents.outlineButton(text: "Retry", onPressed: () { setState(() { _loading = true; _error = null; }); _loadEarnings(); }),
                      ],
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    if (widget.embedded) AppComponents.sectionTitle("Earnings"),
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: AppComponents.cardDecoration(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("Total completed payouts", style: TextStyle(color: Colors.black54, fontSize: 13)),
                          const SizedBox(height: 4),
                          Text(_formatAmount(_totalEarnings),
                              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(child: AppComponents.statChip("Total payouts", "$_totalPayouts")),
                        const SizedBox(width: 12),
                        Expanded(child: AppComponents.statChip("Completed", "${_payouts.where((p) => p['status'] == 'COMPLETED').length}")),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Container(
                      decoration: AppComponents.cardDecoration(),
                      child: Column(
                        children: [
                          AppComponents.tile(title: "Cash out to bank", subtitle: "Instant transfer to linked account", leading: Icons.account_balance_outlined, onTap: () {}),
                          AppComponents.divider(),
                          AppComponents.tile(title: "Payout history", subtitle: "View past transfers", leading: Icons.history, onTap: () {}),
                          AppComponents.divider(),
                          AppComponents.tile(title: "Skill-based incentives", subtitle: "Bonuses for milestones & ratings", leading: Icons.emoji_events_outlined, onTap: () {}),
                        ],
                      ),
                    ),
                    if (_payouts.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      const Text("Recent Payouts", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 10),
                      ..._payouts.map((p) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: AppComponents.cardDecoration(),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(_formatAmount((p['amount'] ?? 0).toDouble()), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                                    const SizedBox(height: 4),
                                    Text("Period: ${p['period'] ?? '--'}", style: const TextStyle(fontSize: 12, color: Colors.black54)),
                                  ],
                                ),
                              ),
                              AppComponents.badge(_statusLabel(p['status']?.toString()), color: _statusColor(p['status']?.toString())),
                            ],
                          ),
                        ),
                      )),
                    ],
                  ],
                ),
    );

    if (widget.embedded) return body;
    return Scaffold(appBar: AppBar(title: const Text("Earnings")), body: body);
  }
}
