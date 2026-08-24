import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:ravelgo_admin/services/admin_api.dart';
import 'package:ravelgo_admin/services/auth_session.dart';
import 'package:ravelgo_admin/theme/app_theme.dart';

enum _LoadState { loading, loaded, error }

class DashboardScreen extends StatefulWidget {
  final bool embedded;
  // Injectable for tests (a MockClient-backed AdminApi); production call
  // sites (AdminShell) omit this and get the real dotenv-configured one.
  final AdminApi? api;
  const DashboardScreen({super.key, this.embedded = false, this.api});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  static const _rides = [128.0, 142.0, 96.0, 180.0, 210.0, 260.0, 174.0];
  static const _days = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];

  late final AdminApi _api = widget.api ??
      AdminApi(
        baseUrl: dotenv.env['API_BASE_URL'] ?? '',
        authTokenProvider: const CognitoAuthTokenProvider(),
      );

  _LoadState _state = _LoadState.loading;
  DashboardKpis? _kpis;
  FleetPresence? _fleet;
  RecentTripsPage? _recentTrips;
  String _errorMessage = "Unable to load dashboard";

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _state = _LoadState.loading);
    try {
      final results = await Future.wait([
        _api.fetchDashboardKpis(),
        _api.fetchFleetPresence(),
        _api.fetchRecentTrips(pageSize: 5),
      ]);
      if (!mounted) return;
      setState(() {
        _kpis = results[0] as DashboardKpis;
        _fleet = results[1] as FleetPresence;
        _recentTrips = results[2] as RecentTripsPage;
        _state = _LoadState.loaded;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e is AdminApiException ? e.message : "Unable to load dashboard";
        _state = _LoadState.error;
      });
    }
  }

  Widget _buildKpiGrid() {
    final kpis = _kpis!;
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.5,
      children: [
        AppComponents.statCard("Active rides now", "${kpis.activeTrips}", Icons.directions_car_filled_outlined),
        AppComponents.statCard("Online drivers", "${kpis.onlineDrivers}", Icons.badge_outlined, color: AppColors.success),
        AppComponents.statCard("Total trips", "${_recentTrips?.total ?? 0}", Icons.payments_outlined, color: AppColors.info),
        AppComponents.statCard("Pending approvals", "${kpis.pendingApprovals}", Icons.pending_actions_outlined, color: AppColors.warning),
      ],
    );
  }

  Widget _buildFleetSection() {
    final online = _fleet!.drivers.where((d) => d.isOnline).toList();
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppComponents.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Online now (${online.length})", style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 12),
          if (online.isEmpty)
            const Text("No drivers online right now", style: TextStyle(fontSize: 12.5, color: Colors.black45))
          else
            ...online.take(6).map((d) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      const Icon(Icons.circle, size: 10, color: AppColors.success),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(d.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                            Text(
                              "${d.vehicle ?? 'No vehicle on file'} · ${d.locationLabel}",
                              style: const TextStyle(fontSize: 11.5, color: Colors.black54),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                )),
        ],
      ),
    );
  }

  Widget _buildBody() {
    switch (_state) {
      case _LoadState.loading:
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 48),
          child: Column(
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 12),
              Text("Loading your dashboard...", style: TextStyle(color: Colors.black54)),
            ],
          ),
        );
      case _LoadState.error:
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: AppComponents.cardDecoration(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("Unable to load dashboard", style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(_errorMessage, style: const TextStyle(fontSize: 12.5, color: Colors.black54)),
              const SizedBox(height: 12),
              AppComponents.outlineButton(text: "Try again", onPressed: _load),
            ],
          ),
        );
      case _LoadState.loaded:
        final maxVal = _rides.reduce((a, b) => a > b ? a : b);
        final trips = _recentTrips?.trips ?? const [];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildKpiGrid(),
            const SizedBox(height: 20),
            _buildFleetSection(),
            const SizedBox(height: 20),
            // "Rides this week" below remains static/mock data — no backend
            // endpoint for historical revenue/ride-volume reporting exists
            // yet, and wiring one is out of scope for this pass (see
            // docs/PRD.md).
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
            if (trips.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(child: Text("No trips yet", style: TextStyle(color: Colors.black54))),
              )
            else
              ...trips.map((t) => Padding(
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
                                Text("${t.pickup} to ${t.destination}", style: const TextStyle(fontSize: 11.5, color: Colors.black54)),
                              ],
                            ),
                          ),
                          Text("₦${t.fare.toStringAsFixed(0)}", style: const TextStyle(fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                  )),
          ],
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [_buildBody()],
      ),
    );

    if (widget.embedded) return body;
    return Scaffold(appBar: AppBar(title: const Text("Dashboard")), body: body);
  }
}
