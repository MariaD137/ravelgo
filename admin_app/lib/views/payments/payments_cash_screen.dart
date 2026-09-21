import 'package:flutter/material.dart';
import 'package:ravelgo_admin/config/currency.dart';
import 'package:ravelgo_admin/services/admin_api.dart';
import 'package:ravelgo_admin/services/api_client.dart';
import 'package:ravelgo_admin/theme/app_theme.dart';
import 'package:ravelgo_admin/widgets/admin_search_field.dart';
import 'package:ravelgo_admin/widgets/pagination_bar.dart';

/// Financial operations: revenue by payment method and per-driver physical
/// cash reconciliation. Reads real Payment/CashRemittance rows — nothing here
/// is estimated or simulated.
class PaymentsCashScreen extends StatefulWidget {
  const PaymentsCashScreen({super.key});

  @override
  State<PaymentsCashScreen> createState() => _PaymentsCashScreenState();
}

class _PaymentsCashScreenState extends State<PaymentsCashScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Payments & Cash'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Overview'),
            Tab(text: 'Cash Reconciliation'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: const [_OverviewTab(), _ReconciliationTab()],
      ),
    );
  }
}

class _OverviewTab extends StatefulWidget {
  const _OverviewTab();
  @override
  State<_OverviewTab> createState() => _OverviewTabState();
}

class _OverviewTabState extends State<_OverviewTab> {
  bool _loading = true;
  String? _error;
  List<AdminPayment> _payments = const [];
  int _page = 1;
  int _totalPages = 1;
  int _total = 0;
  // Whole-table SUCCEEDED revenue per method, computed by the backend — never
  // summed from the rows of one page.
  double _cash = 0;
  double _card = 0;
  double _wallet = 0;
  String? _q;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({int? page}) async {
    if (page != null) _page = page;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await AdminApi.payments(q: _q, page: _page);
      if (!mounted) return;
      if (result.page.isPastEnd) return await _load(page: result.page.totalPages);
      setState(() {
        _payments = result.page.items;
        _total = result.page.total;
        _totalPages = result.page.totalPages;
        _cash = result.cash;
        _card = result.card;
        _wallet = result.wallet;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException && e.statusCode == 403
            ? 'Sign in as an admin to view payments.'
            : e.toString();
        _loading = false;
      });
    }
  }

  Color _methodColor(String m) => switch (m) {
    'CASH' => AppColors.success,
    'CARD' => AppColors.info,
    'WALLET' => AppColors.warning,
    _ => AppColors.textMuted,
  };

  Color _statusColor(String s) => switch (s) {
    'SUCCEEDED' => AppColors.success,
    'FAILED' => AppColors.danger,
    'REFUNDED' => AppColors.warning,
    _ => AppColors.textMuted,
  };

  void _onSearchChanged(String? q) {
    _q = q;
    _load(page: 1);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AdminSearchField(hintText: 'Search rider, driver or trip id…', onChanged: _onSearchChanged),
        Expanded(child: _body()),
      ],
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
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.danger),
              ),
              TextButton(onPressed: _load, child: const Text('Try again')),
            ],
          ),
        ),
      );
    }

    final cash = _cash;
    final card = _card;
    final wallet = _wallet;

    return Column(
      children: [
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _statCard(
                        'Cash collected',
                        cash,
                        AppColors.success,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _statCard('Card revenue', card, AppColors.info),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _statCard(
                        'RavelGo Cash revenue',
                        wallet,
                        AppColors.warning,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _statCard(
                        'Total revenue',
                        cash + card + wallet,
                        AppColors.primaryDark,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const Text(
                  'Payments',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                ),
                const SizedBox(height: 10),
                if (_payments.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text(
                        _q == null ? 'No payments yet.' : 'No payments match "$_q".',
                        style: const TextStyle(color: AppColors.textSecondary),
                      ),
                    ),
                  )
                else
                  ..._payments.map(
                    (p) => Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: AppComponents.cardDecoration(),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  p.riderName.isEmpty ? 'Rider' : p.riderName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Trip ${p.tripId.length > 8 ? p.tripId.substring(0, 8) : p.tripId}',
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                Currency.format(p.amount, decimals: 0),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  AppComponents.badge(
                                    p.method,
                                    color: _methodColor(p.method),
                                  ),
                                  const SizedBox(width: 6),
                                  AppComponents.badge(
                                    p.status,
                                    color: _statusColor(p.status),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        PaginationBar(
          page: _page,
          totalPages: _totalPages,
          total: _total,
          itemLabel: 'payments',
          busy: _loading,
          onPageChanged: (p) => _load(page: p),
        ),
      ],
    );
  }

  Widget _statCard(String label, double amount, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AppComponents.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            Currency.format(amount, decimals: 0),
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReconciliationTab extends StatefulWidget {
  const _ReconciliationTab();
  @override
  State<_ReconciliationTab> createState() => _ReconciliationTabState();
}

class _ReconciliationTabState extends State<_ReconciliationTab> {
  bool _loading = true;
  bool _busy = false;
  String? _error;
  List<CashReconciliationRow> _rows = const [];
  // True only when the ledger/remittance history has grown past what the
  // backend fetches in one call — the figures below are then computed from
  // an incomplete slice of history, not the complete ledger.
  bool _truncated = false;

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
      final result = await AdminApi.cashReconciliation();
      if (!mounted) return;
      setState(() {
        _rows = result.rows;
        _truncated = result.truncated;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException && e.statusCode == 403
            ? 'Your admin role can\'t view cash reconciliation.'
            : e.toString();
        _loading = false;
      });
    }
  }

  Color _statusColor(String s) => switch (s) {
    'CLEAR' => AppColors.success,
    'OUTSTANDING' => AppColors.warning,
    'REVIEW_REQUIRED' => AppColors.danger,
    _ => AppColors.textMuted,
  };

  Future<void> _recordRemittance(CashReconciliationRow row) async {
    final controller = TextEditingController(
      text: row.outstandingCash > 0
          ? row.outstandingCash.toStringAsFixed(0)
          : '',
    );
    final noteController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            'Record cash from ${row.driverName.isEmpty ? row.driverEmail : row.driverName}',
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Outstanding: ${Currency.format(row.outstandingCash, decimals: 0)}',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12.5,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Amount received (₦)',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setDialogState(() {}),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: noteController,
                decoration: const InputDecoration(
                  labelText: 'Note (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: (double.tryParse(controller.text.trim()) ?? 0) > 0
                  ? () => Navigator.pop(context, true)
                  : null,
              child: const Text('Record'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    final amount = double.tryParse(controller.text.trim());
    if (amount == null || amount <= 0) return;

    setState(() => _busy = true);
    try {
      await AdminApi.recordCashRemittance(
        driverId: row.driverId,
        amount: amount,
        note: noteController.text.trim(),
      );
      await _load();
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cash remittance recorded.')),
        );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e is ApiException ? e.message : e.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.danger),
              ),
              TextButton(onPressed: _load, child: const Text('Try again')),
            ],
          ),
        ),
      );
    }
    if (_rows.isEmpty) {
      return Column(
        children: [
          if (_truncated) _truncatedBanner(),
          const Expanded(
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No driver has collected cash yet.',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
            ),
          ),
        ],
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _rows.length + (_truncated ? 1 : 0),
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          if (_truncated) {
            if (i == 0) return _truncatedBanner();
            i -= 1;
          }
          final r = _rows[i];
          return Container(
            padding: const EdgeInsets.all(14),
            decoration: AppComponents.cardDecoration(
              borderColor: r.status == 'REVIEW_REQUIRED'
                  ? AppColors.danger
                  : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        r.driverName.isEmpty ? r.driverEmail : r.driverName,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    AppComponents.badge(
                      r.status.replaceAll('_', ' '),
                      color: _statusColor(r.status),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: _figure('Expected', r.expectedCash)),
                    Expanded(child: _figure('Submitted', r.submittedCash)),
                    Expanded(
                      child: _figure(
                        'Outstanding',
                        r.outstandingCash,
                        color: _statusColor(r.status),
                      ),
                    ),
                  ],
                ),
                Text(
                  '${r.cashTripCount} cash trip${r.cashTripCount == 1 ? '' : 's'}',
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _busy ? null : () => _recordRemittance(r),
                    child: const Text('Record remittance'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _figure(String label, double amount, {Color? color}) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
      ),
      Text(
        Currency.format(amount, decimals: 0),
        style: TextStyle(fontWeight: FontWeight.w700, color: color),
      ),
    ],
  );

  // The backend caps how many ledger/remittance rows it fetches per request
  // (see cash.routes.ts) — this is never silent: when the real history has
  // grown past that cap, the per-driver figures above are computed from an
  // incomplete slice of it, and this screen must say so rather than let an
  // admin mistake a partial reconciliation for the complete one.
  Widget _truncatedBanner() => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 18, color: AppColors.warning),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'This reconciliation covers only the most recent ledger/remittance history — the real history has grown past what one screen can show. Figures below may be incomplete.',
              style: TextStyle(fontSize: 12.5),
            ),
          ),
        ],
      ),
    ),
  );
}
