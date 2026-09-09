import 'package:flutter/material.dart';
import 'package:ravelgo_admin/config/currency.dart';
import 'package:ravelgo_admin/services/admin_api.dart';
import 'package:ravelgo_admin/services/api_client.dart';
import 'package:ravelgo_admin/theme/app_theme.dart';
import 'package:ravelgo_admin/utils/date_utils.dart';
import 'package:ravelgo_admin/views/payments/payments_cash_screen.dart';

/// Marketplace-wide financial rollup — read-only, computed live from the
/// FinancialTransaction ledger on every load (GET /api/admin/financial-
/// dashboard). Open to every Admin preset; no writes happen from this screen.
class FinancialDashboardScreen extends StatefulWidget {
  const FinancialDashboardScreen({super.key});

  @override
  State<FinancialDashboardScreen> createState() => _FinancialDashboardScreenState();
}

class _FinancialDashboardScreenState extends State<FinancialDashboardScreen> {
  bool _loading = true;
  String? _error;
  FinancialDashboard? _data;
  DateTimeRange? _range;

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
      final data = await AdminApi.financialDashboard(from: _range?.start, to: _range?.end);
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException ? e.message : e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 3),
      lastDate: now,
      initialDateRange: _range,
    );
    if (picked == null) return;
    // Include the whole end day.
    final end = DateTime(picked.end.year, picked.end.month, picked.end.day, 23, 59, 59);
    setState(() => _range = DateTimeRange(start: picked.start, end: end));
    _load();
  }

  void _clearRange() {
    setState(() => _range = null);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Financial Dashboard'),
        actions: [
          IconButton(icon: const Icon(Icons.date_range_outlined), tooltip: 'Choose date range', onPressed: _pickRange),
          if (_range != null)
            IconButton(icon: const Icon(Icons.close), tooltip: 'Clear date range', onPressed: _clearRange),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (_error != null ? _errView() : _body()),
    );
  }

  Widget _errView() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.danger)),
            TextButton(onPressed: _load, child: const Text('Try again')),
          ]),
        ),
      );

  Widget _body() {
    final d = _data!;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (_range != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(color: AppColors.primaryContainer, borderRadius: BorderRadius.circular(AppRadius.medium)),
              child: Row(
                children: [
                  const Icon(Icons.calendar_today_outlined, size: 16, color: AppColors.textSecondary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${formatShortDate(_range!.start)} — ${formatShortDate(_range!.end)}',
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                    ),
                  ),
                  TextButton(onPressed: _clearRange, child: const Text('All time')),
                ],
              ),
            )
          else
            const Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: Text('Showing all-time figures. Tap the date icon above to filter by range.',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            ),
          _section('Marketplace', [
            _tile('Gross marketplace volume', d.grossMarketplaceVolume, Icons.storefront_outlined, AppColors.textPrimary),
            _tile('Ride revenue', d.rideRevenue, Icons.directions_car_outlined, AppColors.info),
            _tile('Delivery revenue', d.deliveryRevenue, Icons.local_shipping_outlined, AppColors.info),
          ]),
          _section('RavelGo', [
            _tile('Commission revenue', d.ravelgoRevenue, Icons.account_balance_outlined, AppColors.success),
          ]),
          _section('Drivers', [
            _tile('Driver earnings', d.driverEarnings, Icons.badge_outlined, AppColors.textPrimary),
          ]),
          _section('Adjustments', [
            _tile('Refunds', d.refunds, Icons.undo_outlined, AppColors.error),
            _tile('Cancellation fees', d.cancellationFees, Icons.cancel_outlined, AppColors.warning),
            _tile('Waiting charges', d.waitingCharges, Icons.hourglass_bottom_outlined, AppColors.warning),
          ]),
          AppComponents.sectionTitle('Cash'),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: AppComponents.cardDecoration(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.payments_outlined, color: AppColors.textSecondary, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text('Commission recorded against cash',
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                    ),
                    Text(Currency.format(d.cashCommissionRecorded, decimals: 0),
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'This is commission booked against CASH transactions in the window above — it is not yet net of '
                  'what drivers have actually remitted. See Cash Reconciliation for the true outstanding balance '
                  'per driver.',
                  style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 10),
                TextButton.icon(
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PaymentsCashScreen())),
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: const Text('Open Cash Reconciliation'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(String title, List<Widget> tiles) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppComponents.sectionTitle(title),
        LayoutBuilder(
          builder: (context, constraints) {
            const spacing = 12.0;
            final isNarrow = constraints.maxWidth < 420;
            final cardWidth = isNarrow ? constraints.maxWidth : (constraints.maxWidth - spacing) / 2;
            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: [for (final t in tiles) SizedBox(width: cardWidth, child: t)],
            );
          },
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _tile(String label, double value, IconData icon, Color color) {
    return AppComponents.statCard(label, Currency.format(value, decimals: 0), icon, color: color);
  }
}
