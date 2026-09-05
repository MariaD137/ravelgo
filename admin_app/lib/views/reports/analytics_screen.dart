import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ravelgo_admin/config/currency.dart';
import 'package:ravelgo_admin/services/admin_api.dart';
import 'package:ravelgo_admin/services/api_client.dart';
import 'package:ravelgo_admin/theme/app_theme.dart';

/// Real 7-day revenue and completed-trips aggregates (GET /api/admin/analytics),
/// computed from actual Payment and Trip rows. There's no tracked "driver
/// online hours" anywhere in the backend, so that metric is honestly labeled
/// unavailable instead of shown with a fabricated number.
class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  bool _loading = true;
  String? _error;
  List<AnalyticsDay> _days = const [];

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
      final days = await AdminApi.analytics();
      if (!mounted) return;
      setState(() {
        _days = days;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException && e.statusCode == 403
            ? 'Sign in as an admin to view analytics.'
            : e.toString();
        _loading = false;
      });
    }
  }

  String _weekdayLabel(String isoDate) {
    final date = DateTime.tryParse(isoDate);
    if (date == null) return isoDate;
    const names = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
    return names[date.weekday - 1];
  }

  Widget _barChart(String title, List<double> values) {
    final maxVal = values.isEmpty ? 1.0 : values.reduce((a, b) => a > b ? a : b);
    final safeMax = maxVal <= 0 ? 1.0 : maxVal;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppComponents.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 16),
          SizedBox(
            height: 110,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(_days.length, (i) {
                final h = 90 * (values[i] / safeMax);
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Container(
                          height: h,
                          decoration: BoxDecoration(
                            color: i == _days.length - 1 ? AppColors.primary : AppColors.primary.withValues(alpha: 0.35),
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(_weekdayLabel(_days[i].date), style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Reports & Analytics")),
      body: _loading ? const Center(child: CircularProgressIndicator()) : (_error != null ? _err() : _body()),
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

  Widget _body() {
    final revenue = _days.map((d) => d.revenue).toList();
    final trips = _days.map((d) => d.completedTrips.toDouble()).toList();
    final totalRevenue = revenue.fold(0.0, (a, b) => a + b);
    final totalTrips = _days.fold(0, (a, d) => a + d.completedTrips);

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(20),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Row(
            children: [
              Expanded(
                  child: AppComponents.statCard("7-day ride revenue", Currency.format(totalRevenue, decimals: 0),
                      Icons.trending_up, color: AppColors.success)),
              const SizedBox(width: 12),
              Expanded(
                  child: AppComponents.statCard("Completed trips", "$totalTrips", Icons.check_circle_outline,
                      color: AppColors.info)),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: AppComponents.cardDecoration(),
            child: const Row(
              children: [
                Icon(Icons.info_outline, size: 18, color: AppColors.textSecondary),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    "Driver online hours aren't tracked by the backend yet, so that metric isn't shown here.",
                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (_days.isEmpty)
            const Center(child: Padding(padding: EdgeInsets.all(24), child: Text("No data yet.", style: TextStyle(color: AppColors.textSecondary))))
          else ...[
            _barChart("Ride revenue this week (${Currency.symbol})", revenue),
            const SizedBox(height: 16),
            _barChart("Completed trips this week", trips),
          ],
          const SizedBox(height: 20),
          AppComponents.outlineButton(
              text: "Export report (copy CSV)",
              onPressed: _days.isEmpty
                  ? null
                  : () {
                      final buffer = StringBuffer("date,revenue,completed_trips\n");
                      for (final d in _days) {
                        buffer.writeln("${d.date},${d.revenue},${d.completedTrips}");
                      }
                      Clipboard.setData(ClipboardData(text: buffer.toString()));
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('Report CSV copied to clipboard - paste it into a spreadsheet'),
                      ));
                    }),
        ],
      ),
    );
  }
}
