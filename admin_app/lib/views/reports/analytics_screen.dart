import 'package:flutter/material.dart';
import 'package:ravelgo_admin/services/api_client.dart';
import 'package:ravelgo_admin/theme/app_theme.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  bool _loading = true;
  String? _error;
  double _weeklyRevenue = 0;
  double _driverOnlineHours = 0;
  List<double> _revenue = [];
  List<double> _hours = [];

  static const _days = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final response = await ApiClient().get('/admin/dashboard');
      final dashboard = response as Map<String, dynamic>;
      if (!mounted) return;

      final revenueData = dashboard['weeklyRevenue'] as List<dynamic>? ?? [];
      final hoursData = dashboard['weeklyDriverHours'] as List<dynamic>? ?? [];

      final revenueList = revenueData.map((e) => (e as num).toDouble()).toList();
      final hoursList = hoursData.map((e) => (e as num).toDouble()).toList();

      final totalRevenue = (dashboard['totalRevenue'] as num?)?.toDouble() ??
          (revenueList.isNotEmpty ? revenueList.reduce((a, b) => a + b) : 0.0);
      final totalHours = (dashboard['totalDriverHours'] as num?)?.toDouble() ??
          (hoursList.isNotEmpty ? hoursList.reduce((a, b) => a + b) : 0.0);

      setState(() {
        _weeklyRevenue = totalRevenue;
        _driverOnlineHours = totalHours;
        _revenue = revenueList;
        _hours = hoursList;
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

  String _formatRevenue(double value) {
    if (value >= 1000000) {
      return '₦${(value / 1000000).toStringAsFixed(2)}M';
    } else if (value >= 1000) {
      return '₦${(value / 1000).toStringAsFixed(0)}K';
    }
    return '₦${value.toStringAsFixed(0)}';
  }

  Widget _barChart(String title, List<double> values) {
    if (values.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: AppComponents.cardDecoration(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            const SizedBox(height: 16),
            const Center(child: Text("No data available", style: TextStyle(color: Colors.black54))),
          ],
        ),
      );
    }

    final maxVal = values.reduce((a, b) => a > b ? a : b);
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
              children: List.generate(values.length, (i) {
                final h = maxVal > 0 ? 90 * (values[i] / maxVal) : 0.0;
                final dayLabel = i < _days.length ? _days[i] : '';
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Container(
                          height: h,
                          decoration: BoxDecoration(
                            color: i == values.length - 1 ? AppColors.primary : AppColors.primary.withValues(alpha: 0.35),
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(dayLabel, style: const TextStyle(fontSize: 11, color: Colors.black54)),
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
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text("Reports & Analytics")),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text("Reports & Analytics")),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.red),
                const SizedBox(height: 12),
                const Text('Failed to load analytics', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                const SizedBox(height: 8),
                Text(_error!, style: const TextStyle(fontSize: 12, color: Colors.black54), textAlign: TextAlign.center),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () { setState(() { _loading = true; _error = null; }); _loadData(); },
                  child: const Text("Retry"),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text("Reports & Analytics")),
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Row(
              children: [
                Expanded(child: AppComponents.statCard("Weekly revenue", _formatRevenue(_weeklyRevenue), Icons.trending_up, color: AppColors.success)),
                const SizedBox(width: 12),
                Expanded(child: AppComponents.statCard("Driver online hours", "${_driverOnlineHours.toStringAsFixed(0)}h", Icons.access_time, color: AppColors.info)),
              ],
            ),
            const SizedBox(height: 16),
            _barChart("Revenue this week (₦)", _revenue),
            const SizedBox(height: 16),
            _barChart("Driver online hours this week", _hours),
            const SizedBox(height: 20),
            AppComponents.outlineButton(
              text: "Export report",
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Feature coming soon')),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
