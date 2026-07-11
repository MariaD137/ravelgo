import 'package:flutter/material.dart';
import 'package:ravelgo_admin/theme/app_theme.dart';

class AnalyticsScreen extends StatelessWidget {
  const AnalyticsScreen({super.key});

  static const _revenue = [820000.0, 910000.0, 760000.0, 1040000.0, 1180000.0, 1350000.0, 1020000.0];
  static const _hours = [64.0, 72.0, 58.0, 80.0, 91.0, 110.0, 76.0];
  static const _days = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];

  Widget _barChart(String title, List<double> values, {String Function(double)? formatter}) {
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
                final h = 90 * (values[i] / maxVal);
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
                        Text(_days[i], style: const TextStyle(fontSize: 11, color: Colors.black54)),
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
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Row(
            children: [
              Expanded(child: AppComponents.statCard("Weekly revenue", "₦7.08M", Icons.trending_up, color: AppColors.success)),
              const SizedBox(width: 12),
              Expanded(child: AppComponents.statCard("Driver online hours", "551h", Icons.access_time, color: AppColors.info)),
            ],
          ),
          const SizedBox(height: 16),
          _barChart("Revenue this week (₦)", _revenue),
          const SizedBox(height: 16),
          _barChart("Driver online hours this week", _hours),
          const SizedBox(height: 20),
          AppComponents.outlineButton(text: "Export report", onPressed: () {}),
        ],
      ),
    );
  }
}
