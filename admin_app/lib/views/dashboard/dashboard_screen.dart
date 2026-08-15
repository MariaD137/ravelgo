import 'package:flutter/material.dart';
import 'package:ravelgo_admin/services/api_client.dart';
import 'package:ravelgo_admin/theme/app_theme.dart';
import 'package:ravelgo_admin/utils/date_utils.dart';

class DashboardScreen extends StatefulWidget {
  final bool embedded;
  const DashboardScreen({super.key, this.embedded = false});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool _loading = true;
  String? _error;

  int _activeTrips = 0;
  int _onlineDrivers = 0;
  int _pendingApprovals = 0;
  int _totalRiders = 0;
  int _totalDrivers = 0;
  int _totalTrips = 0;
  List<Map<String, dynamic>> _recentTrips = [];

  static const _rides = [128.0, 142.0, 96.0, 180.0, 210.0, 260.0, 174.0];
  static const _days = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final results = await Future.wait([
        ApiClient().get('/admin/dashboard'),
        ApiClient().get('/riders', queryParams: {'pageSize': '1'}),
        ApiClient().get('/drivers', queryParams: {'pageSize': '1'}),
        ApiClient().get('/trips', queryParams: {'pageSize': '5'}),
      ]);

      final dashboard = results[0] as Map<String, dynamic>;
      final ridersPage = results[1] as Map<String, dynamic>;
      final driversPage = results[2] as Map<String, dynamic>;
      final tripsPage = results[3] as Map<String, dynamic>;

      if (!mounted) return;
      setState(() {
        _activeTrips = dashboard['activeTrips'] ?? 0;
        _onlineDrivers = dashboard['onlineDrivers'] ?? 0;
        _pendingApprovals = dashboard['pendingApprovals'] ?? 0;
        _totalRiders = ridersPage['total'] ?? 0;
        _totalDrivers = driversPage['total'] ?? 0;
        _totalTrips = tripsPage['total'] ?? 0;
        _recentTrips = List<Map<String, dynamic>>.from(tripsPage['data'] ?? []);
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

  String _tripRiderName(Map<String, dynamic> trip) {
    final rider = trip['rider'] as Map<String, dynamic>?;
    if (rider == null) return 'Unknown';
    return '${rider['firstName'] ?? ''} ${rider['lastName'] ?? ''}'.trim();
  }

  String _tripDriverName(Map<String, dynamic> trip) {
    final driver = trip['driver'] as Map<String, dynamic>?;
    if (driver == null) return 'Unassigned';
    final user = driver['user'] as Map<String, dynamic>?;
    if (user == null) return 'Unknown';
    return '${user['firstName'] ?? ''} ${user['lastName'] ?? ''}'.trim();
  }

  double _tripFare(Map<String, dynamic> trip) {
    return (trip['finalFare'] ?? trip['estimatedFare'] ?? 0).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      final loader = const Center(child: CircularProgressIndicator());
      if (widget.embedded) return loader;
      return Scaffold(appBar: AppBar(title: const Text("Dashboard")), body: loader);
    }

    if (_error != null) {
      final errorView = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 12),
              Text('Failed to load dashboard', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(fontSize: 12, color: Colors.black54), textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: () { setState(() { _loading = true; _error = null; }); _loadData(); }, child: const Text("Retry")),
            ],
          ),
        ),
      );
      if (widget.embedded) return errorView;
      return Scaffold(appBar: AppBar(title: const Text("Dashboard")), body: errorView);
    }

    final maxVal = _rides.reduce((a, b) => a > b ? a : b);
    final body = RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.5,
            children: [
              AppComponents.statCard("Active rides now", "$_activeTrips", Icons.directions_car_filled_outlined),
              AppComponents.statCard("Online drivers", "$_onlineDrivers", Icons.badge_outlined, color: AppColors.success),
              AppComponents.statCard("Total trips", "$_totalTrips", Icons.payments_outlined, color: AppColors.info),
              AppComponents.statCard("Pending approvals", "$_pendingApprovals", Icons.pending_actions_outlined, color: AppColors.warning),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: AppComponents.cardDecoration(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Rides this week", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 16),
                SizedBox(
                  height: 120,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: List.generate(_rides.length, (i) {
                      final h = 100 * (_rides[i] / maxVal);
                      return Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Container(
                                height: h,
                                decoration: BoxDecoration(
                                  color: i == _rides.length - 1 ? AppColors.primary : AppColors.primary.withValues(alpha: 0.35),
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
          ),
          const SizedBox(height: 20),
          AppComponents.sectionTitle("Recent trips"),
          if (_recentTrips.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: Text("No trips yet", style: TextStyle(color: Colors.black54))),
            )
          else
            ..._recentTrips.map((t) => Padding(
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
                              Text("${_tripRiderName(t)}  →  ${_tripDriverName(t)}", style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                              const SizedBox(height: 4),
                              Text("${t['pickup'] ?? ''} to ${t['destination'] ?? ''}", style: const TextStyle(fontSize: 11.5, color: Colors.black54)),
                            ],
                          ),
                        ),
                        Text("₦${_tripFare(t).toStringAsFixed(0)}", style: const TextStyle(fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                )),
        ],
      ),
    );

    if (widget.embedded) return body;
    return Scaffold(appBar: AppBar(title: const Text("Dashboard")), body: body);
  }
}
