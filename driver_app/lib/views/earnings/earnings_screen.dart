import 'package:flutter/material.dart';
import 'package:ravelgo_driver_app/services/api_client.dart';
import 'package:ravelgo_driver_app/services/driver_api.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';
import 'package:ravelgo_driver_app/views/earnings/cash_out_screen.dart';
import 'package:ravelgo_driver_app/views/earnings/payout_history_screen.dart';
import 'package:ravelgo_driver_app/views/incentives/incentives_screen.dart';

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
  double _weekTotal = 0;
  int _completedCount = 0;
  double _rating = 5.0;
  List<double> _week = List.filled(7, 0); // Mon..Sun of the current week

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
      final results = await Future.wait([DriverApi.myTrips(), DriverApi.getMe()]);
      final trips = results[0] as List<DriverTrip>;
      final record = results[1] as DriverRecord;

      // Real earnings = completed trips' fares. Bucket this week's completed
      // trips into Mon..Sun for the bar chart.
      final now = DateTime.now();
      final monday = DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1));
      final week = List<double>.filled(7, 0);
      double weekTotal = 0;
      int completed = 0;
      for (final t in trips) {
        if (t.status != 'COMPLETED') continue;
        completed++;
        final d = t.requestedAt;
        final dayIndex = d.difference(monday).inDays;
        if (dayIndex >= 0 && dayIndex < 7) {
          week[dayIndex] += t.fare;
          weekTotal += t.fare;
        }
      }
      if (!mounted) return;
      setState(() {
        _week = week;
        _weekTotal = weekTotal;
        _completedCount = completed;
        _rating = record.rating;
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

  @override
  Widget build(BuildContext context) {
    final maxVal = _week.fold<double>(0, (a, b) => b > a ? b : a);
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
                    const Text("This week", style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                    const SizedBox(height: 4),
                    _loading
                        ? const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: SizedBox(height: 24, width: 24, child: CircularProgressIndicator(strokeWidth: 2)))
                        : Text("\$${_weekTotal.toStringAsFixed(2)}",
                            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 20),
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: List.generate(_week.length, (i) {
                          final h = maxVal <= 0 ? 0.0 : _chartBarMaxHeight * (_week[i] / maxVal);
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
                  ],
                ),
              ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: AppComponents.statChip("Trips completed", _loading ? "…" : "$_completedCount")),
                const SizedBox(width: 12),
                Expanded(child: AppComponents.statChip("Avg. rating", _loading ? "…" : _rating.toStringAsFixed(1))),
              ],
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
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CashOutScreen()))),
                  AppComponents.divider(),
                  AppComponents.tile(
                      title: "Payout history",
                      subtitle: "View past transfers",
                      leading: Icons.history,
                      onTap: () =>
                          Navigator.push(context, MaterialPageRoute(builder: (_) => const PayoutHistoryScreen()))),
                  AppComponents.divider(),
                  AppComponents.tile(
                      title: "Skill-based incentives",
                      subtitle: "Bonuses for milestones & ratings",
                      leading: Icons.emoji_events_outlined,
                      onTap: () =>
                          Navigator.push(context, MaterialPageRoute(builder: (_) => const IncentivesScreen()))),
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
}
