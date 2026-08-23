import 'package:flutter/material.dart';
import 'package:ravelgo_admin/services/api/admin_api.dart';
import 'package:ravelgo_admin/services/api/api_client.dart';
import 'package:ravelgo_admin/theme/app_theme.dart';

class AnalyticsScreen extends StatefulWidget {
  final AdminApi? adminApi;
  const AnalyticsScreen({super.key, this.adminApi});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  late final AdminApi _api = widget.adminApi ?? AdminApi(ApiClient());
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = _api.getWeeklyReport();
  }

  Future<void> _refresh() async {
    setState(() => _future = _api.getWeeklyReport());
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Reports & Analytics")),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<Map<String, dynamic>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return ListView(
                children: [
                  const SizedBox(height: 80),
                  Center(child: Text('Failed to load report: ${snapshot.error}', textAlign: TextAlign.center)),
                  const SizedBox(height: 12),
                  Center(child: TextButton(onPressed: _refresh, child: const Text('Retry'))),
                ],
              );
            }
            final report = snapshot.data!;
            final revenue = (report['revenueThisWeek'] as num).toDouble();
            final tripsCompleted = report['tripsCompletedThisWeek'] as int;
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Row(
                  children: [
                    Expanded(child: AppComponents.statCard("Revenue this week", "₦${revenue.toStringAsFixed(0)}", Icons.trending_up, color: AppColors.success)),
                    const SizedBox(width: 12),
                    Expanded(child: AppComponents.statCard("Trips completed", "$tripsCompleted", Icons.check_circle_outline, color: AppColors.info)),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
