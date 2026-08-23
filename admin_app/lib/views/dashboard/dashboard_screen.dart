import 'package:flutter/material.dart';
import 'package:ravelgo_admin/models/trip_record.dart';
import 'package:ravelgo_admin/services/api/api_client.dart';
import 'package:ravelgo_admin/services/api/dashboard_api.dart';
import 'package:ravelgo_admin/services/api/trip_api.dart';
import 'package:ravelgo_admin/theme/app_theme.dart';
import 'package:ravelgo_admin/utils/date_utils.dart';

class DashboardScreen extends StatefulWidget {
  final bool embedded;
  final DashboardApi? dashboardApi;
  final TripApi? tripApi;
  const DashboardScreen({super.key, this.embedded = false, this.dashboardApi, this.tripApi});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late final DashboardApi _dashboardApi = widget.dashboardApi ?? DashboardApi(ApiClient());
  late final TripApi _tripApi = widget.tripApi ?? TripApi(ApiClient());

  late Future<Map<String, dynamic>> _kpisFuture;
  late Future<List<TripRecord>> _recentTripsFuture;

  @override
  void initState() {
    super.initState();
    _kpisFuture = _dashboardApi.getKpis();
    _recentTripsFuture = _loadRecentTrips();
  }

  Future<List<TripRecord>> _loadRecentTrips() async {
    final raw = await _tripApi.listAll(page: 1, pageSize: 4);
    return raw.map(TripRecord.fromJson).toList();
  }

  Future<void> _refresh() async {
    setState(() {
      _kpisFuture = _dashboardApi.getKpis();
      _recentTripsFuture = _loadRecentTrips();
    });
    await Future.wait([_kpisFuture, _recentTripsFuture]);
  }

  @override
  Widget build(BuildContext context) {
    final body = RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          FutureBuilder<Map<String, dynamic>>(
            future: _kpisFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (snapshot.hasError) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text('Failed to load dashboard KPIs: ${snapshot.error}'),
                );
              }
              final kpis = snapshot.data!;
              return GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.5,
                children: [
                  AppComponents.statCard("Active rides now", "${kpis['activeTrips']}", Icons.directions_car_filled_outlined),
                  AppComponents.statCard("Online drivers", "${kpis['onlineDrivers']}", Icons.badge_outlined, color: AppColors.success),
                  AppComponents.statCard("Pending approvals", "${kpis['pendingApprovals']}", Icons.pending_actions_outlined, color: AppColors.warning),
                ],
              );
            },
          ),
          const SizedBox(height: 20),
          AppComponents.sectionTitle("Recent trips"),
          FutureBuilder<List<TripRecord>>(
            future: _recentTripsFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (snapshot.hasError) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text('Failed to load recent trips: ${snapshot.error}'),
                );
              }
              final trips = snapshot.data ?? const [];
              if (trips.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text('No trips yet.', style: TextStyle(color: Colors.black54)),
                );
              }
              return Column(
                children: trips
                    .map((t) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: AppComponents.cardDecoration(),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text("${t.riderName}  →  ${t.driverName}", style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                                      const SizedBox(height: 4),
                                      Text("${t.pickup} to ${t.destination} · ${formatFriendlyDate(t.date)}", style: const TextStyle(fontSize: 11.5, color: Colors.black54)),
                                    ],
                                  ),
                                ),
                                Text("₦${t.fare.toStringAsFixed(0)}", style: const TextStyle(fontWeight: FontWeight.w700)),
                              ],
                            ),
                          ),
                        ))
                    .toList(),
              );
            },
          ),
        ],
      ),
    );

    if (widget.embedded) return body;
    return Scaffold(appBar: AppBar(title: const Text("Dashboard")), body: body);
  }
}
