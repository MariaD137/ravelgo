import 'package:flutter/material.dart';
import 'package:ravelgo_driver_app/config/currency.dart';
import 'package:ravelgo_driver_app/services/api_client.dart';
import 'package:ravelgo_driver_app/services/driver_api.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';
import 'package:ravelgo_driver_app/views/earnings/cash_out_screen.dart';
import 'package:ravelgo_driver_app/views/earnings/payout_history_screen.dart';
import 'package:ravelgo_driver_app/views/incentives/incentives_screen.dart';
import 'package:ravelgo_driver_app/widgets/app_page_route.dart';

/// A gross/commission/net split for one period, built entirely from real
/// backend numbers (Trip.driverEarnings/platformCommission,
/// CourierRequest.driverEarnings/platformCommission) — never computed by
/// this app. There is no backend aggregation endpoint yet, so this screen
/// fetches the raw trip/delivery lists and sums their own settled fields:
/// gross is reconstructed as driverEarnings + platformCommission (which
/// reconstructs the exact commissioned fare, not a guess), commission is the
/// summed platformCommission, and net is the summed driverEarnings. Only
/// COMPLETED trips / DELIVERED deliveries with a non-null driverEarnings
/// (i.e. actually paid) are counted — a trip whose payment hasn't settled
/// yet contributes nothing here, rather than an estimate.
class _EarningsTotals {
  double gross = 0;
  double commission = 0;
  double net = 0;

  void add({required double net, required double commission}) {
    this.net += net;
    this.commission += commission;
    gross += net + commission;
  }
}

class EarningsScreen extends StatefulWidget {
  final bool embedded;
  const EarningsScreen({super.key, this.embedded = false});

  @override
  State<EarningsScreen> createState() => _EarningsScreenState();
}

class _EarningsScreenState extends State<EarningsScreen> {
  static const _days = ["M", "T", "W", "T", "F", "S", "S"];
  static const _chartBarMaxHeight = 100.0;

  bool _loading = true;
  String? _error;
  double _rating = 5.0;

  final _today = _EarningsTotals();
  final _week = _EarningsTotals();
  final _month = _EarningsTotals();

  int _tripsCompletedThisWeek = 0;
  int _deliveriesCompletedThisWeek = 0;

  // Mon..Sun net (driverEarnings) for the bar chart — net is what the driver
  // actually receives, so that's what this charts, not the raw gross fare.
  List<double> _weekChart = List.filled(7, 0);

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
      final results = await Future.wait([DriverApi.myTrips(), DriverApi.myDeliveries(), DriverApi.getMe()]);
      final trips = results[0] as List<DriverTrip>;
      final deliveries = results[1] as List<CourierRequest>;
      final record = results[2] as DriverRecord;

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final monday = today.subtract(Duration(days: now.weekday - 1));
      final monthStart = DateTime(now.year, now.month, 1);

      final todayTotals = _EarningsTotals();
      final weekTotals = _EarningsTotals();
      final monthTotals = _EarningsTotals();
      final weekChart = List<double>.filled(7, 0);
      var tripsThisWeek = 0;
      var deliveriesThisWeek = 0;

      // Settled trips only — driverEarnings is null until payment actually
      // clears, so an in-flight or unpaid trip contributes nothing here.
      for (final t in trips) {
        if (t.status != 'COMPLETED' || t.driverEarnings == null) continue;
        final net = t.driverEarnings!;
        final commission = t.platformCommission ?? 0;
        final settledAt = t.completedAt ?? t.requestedAt;

        if (!settledAt.isBefore(monthStart)) monthTotals.add(net: net, commission: commission);
        if (!settledAt.isBefore(today)) todayTotals.add(net: net, commission: commission);
        final dayIndex = settledAt.difference(monday).inDays;
        if (dayIndex >= 0 && dayIndex < 7) {
          weekTotals.add(net: net, commission: commission);
          weekChart[dayIndex] += net;
          tripsThisWeek++;
        }
      }

      // Settled deliveries only — same non-null-driverEarnings rule.
      for (final r in deliveries) {
        if (r.status != 'DELIVERED' || r.driverEarnings == null) continue;
        final net = r.driverEarnings!;
        final commission = r.platformCommission ?? 0;
        final settledAt = r.deliveredAt ?? r.requestedAt;

        if (!settledAt.isBefore(monthStart)) monthTotals.add(net: net, commission: commission);
        if (!settledAt.isBefore(today)) todayTotals.add(net: net, commission: commission);
        final dayIndex = settledAt.difference(monday).inDays;
        if (dayIndex >= 0 && dayIndex < 7) {
          weekTotals.add(net: net, commission: commission);
          weekChart[dayIndex] += net;
          deliveriesThisWeek++;
        }
      }

      if (!mounted) return;
      setState(() {
        _today
          ..gross = todayTotals.gross
          ..commission = todayTotals.commission
          ..net = todayTotals.net;
        _week
          ..gross = weekTotals.gross
          ..commission = weekTotals.commission
          ..net = weekTotals.net;
        _month
          ..gross = monthTotals.gross
          ..commission = monthTotals.commission
          ..net = monthTotals.net;
        _weekChart = weekChart;
        _tripsCompletedThisWeek = tripsThisWeek;
        _deliveriesCompletedThisWeek = deliveriesThisWeek;
        _rating = record.rating;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = describeApiFailure(e, what: 'your earnings');
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final maxVal = _weekChart.fold<double>(0, (a, b) => b > a ? b : a);
    final body = SafeArea(
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(20),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            if (widget.embedded) AppComponents.sectionTitle("Earnings"),
            if (_error != null)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: AppComponents.cardDecoration(),
                child: Text(_error!, style: const TextStyle(color: AppColors.danger)),
              )
            else
              Container(
                padding: const EdgeInsets.all(20),
                decoration: AppComponents.cardDecoration(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("This week · Net earnings", style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                    const SizedBox(height: 4),
                    _loading
                        ? const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: SizedBox(height: 24, width: 24, child: CircularProgressIndicator(strokeWidth: 2)))
                        : Text(Currency.format(_week.net),
                            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 20),
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: List.generate(_weekChart.length, (i) {
                          final h = maxVal <= 0 ? 0.0 : _chartBarMaxHeight * (_weekChart[i] / maxVal);
                          return Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  Container(
                                    height: h,
                                    decoration: BoxDecoration(
                                      color: AppColors.primary.withValues(alpha: h > 0 ? 0.9 : 0.15),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(_days[i], style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                                ],
                              ),
                            ),
                          );
                        }),
                      ),
                    ),
                    const SizedBox(height: 20),
                    AppComponents.divider(),
                    const SizedBox(height: 12),
                    // The real backend split for this week — RavelGo's 20%
                    // commission and the driver's actual take-home, sourced
                    // entirely from Trip/CourierRequest.driverEarnings and
                    // .platformCommission, never computed in this app.
                    _breakdownRow("Gross earnings", _week.gross),
                    _breakdownRow("RavelGo commission", -_week.commission, muted: true),
                    _breakdownRow("Net earnings", _week.net, bold: true),
                  ],
                ),
              ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: _periodCard("Today", _today)),
                const SizedBox(width: 12),
                Expanded(child: _periodCard("This month", _month)),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                    child: AppComponents.statChip(
                        "Trips completed", _loading ? "…" : "$_tripsCompletedThisWeek")),
                const SizedBox(width: 12),
                Expanded(
                    child: AppComponents.statChip(
                        "Deliveries completed", _loading ? "…" : "$_deliveriesCompletedThisWeek")),
              ],
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: 0.5,
                child: Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: AppComponents.statChip("Avg. rating", _loading ? "…" : _rating.toStringAsFixed(1)),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              decoration: AppComponents.cardDecoration(),
              child: Column(
                children: [
                  AppComponents.tile(
                      title: "Payout account",
                      subtitle: "Where your earnings are paid out",
                      leading: Icons.account_balance_outlined,
                      onTap: () => Navigator.push(context, AppPageRoute(builder: (_) => const CashOutScreen()))),
                  AppComponents.divider(),
                  AppComponents.tile(
                      title: "Payout history",
                      subtitle: "View past transfers",
                      leading: Icons.history,
                      onTap: () =>
                          Navigator.push(context, AppPageRoute(builder: (_) => const PayoutHistoryScreen()))),
                  AppComponents.divider(),
                  AppComponents.tile(
                      title: "Skill-based incentives",
                      subtitle: "Bonuses for milestones & ratings",
                      leading: Icons.emoji_events_outlined,
                      onTap: () =>
                          Navigator.push(context, AppPageRoute(builder: (_) => const IncentivesScreen()))),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    if (widget.embedded) return body;
    return Scaffold(appBar: AppBar(title: const Text("Earnings")), body: body);
  }

  /// Compact Gross/Commission/Net card for Today / This month, alongside the
  /// primary "This week" card above.
  Widget _periodCard(String label, _EarningsTotals t) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AppComponents.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
          const SizedBox(height: 6),
          Text(_loading ? "…" : Currency.format(t.net, decimals: 0),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          const Text("Net earnings", style: TextStyle(fontSize: 10.5, color: AppColors.textMuted)),
          const SizedBox(height: 8),
          _miniRow("Gross", t.gross),
          _miniRow("Commission", -t.commission),
        ],
      ),
    );
  }

  Widget _miniRow(String label, double amount) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
          Text(_loading ? "…" : Currency.format(amount, decimals: 0),
              style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
        ],
      ),
    );
  }

  Widget _breakdownRow(String label, double amount, {bool bold = false, bool muted = false}) {
    final color = muted ? AppColors.textSecondary : null;
    final prefix = amount < 0 ? '-' : '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(fontSize: 14, fontWeight: bold ? FontWeight.w700 : FontWeight.w500, color: color)),
          Text('$prefix${Currency.format(amount.abs())}',
              style: TextStyle(fontSize: 14, fontWeight: bold ? FontWeight.w700 : FontWeight.w500, color: color)),
        ],
      ),
    );
  }
}
