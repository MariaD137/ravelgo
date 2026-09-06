import 'package:flutter/material.dart';
import 'package:ravelgo_admin/services/admin_api.dart';
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
  static const _days = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
  static const _chartBarMaxHeight = 100.0;

  bool _loading = true;
  String? _error;
  DashboardStats? _stats;
  List<AdminTrip> _trips = const [];
  double _revenue = 0;
  List<double> _week = List.filled(7, 0);

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
      final results = await Future.wait([AdminApi.dashboard(), AdminApi.trips()]);
      final stats = results[0] as DashboardStats;
      final trips = results[1] as List<AdminTrip>;

      final now = DateTime.now();
      final monday = DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1));
      final week = List<double>.filled(7, 0);
      double revenue = 0;
      for (final t in trips) {
        final di = t.requestedAt.difference(monday).inDays;
        if (di >= 0 && di < 7) week[di] += 1;
        if (t.status == 'COMPLETED') revenue += t.fare;
      }
      if (!mounted) return;
      setState(() {
        _stats = stats;
        _trips = trips;
        _revenue = revenue;
        _week = week;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException && e.statusCode == 403
            ? 'Sign in as an admin to view the dashboard.'
            : e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final Widget body = _loading
        ? const Center(child: CircularProgressIndicator())
        : (_error != null ? _errorView() : _content());
    if (widget.embedded) return body;
    return Scaffold(appBar: AppBar(title: const Text("Dashboard")), body: body);
  }

  Widget _errorView() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.danger)),
              TextButton(onPressed: _load, child: const Text('Try again')),
            ],
          ),
        ),
      );

  Widget _content() {
    final maxVal = _week.fold<double>(0, (a, b) => b > a ? b : a);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              const spacing = 12.0;
              final cardWidth = (constraints.maxWidth - spacing) / 2;
              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: [
                  SizedBox(
                      width: cardWidth,
                      child: AppComponents.statCard(
                          "Active rides now", "${_stats!.activeTrips}", Icons.directions_car_filled_outlined)),
                  SizedBox(
                      width: cardWidth,
                      child: AppComponents.statCard("Online drivers", "${_stats!.onlineDrivers}", Icons.badge_outlined,
                          color: AppColors.success)),
                  SizedBox(
                      width: cardWidth,
                      child: AppComponents.statCard("Revenue (completed)", "₦${_revenue.toStringAsFixed(0)}",
                          Icons.payments_outlined,
                          color: AppColors.info)),
                  SizedBox(
                      width: cardWidth,
                      child: AppComponents.statCard(
                          "Pending approvals", "${_stats!.pendingApprovals}", Icons.pending_actions_outlined,
                          color: AppColors.warning)),
                  SizedBox(
                      width: cardWidth,
                      child: AppComponents.statCard("Available drivers", "${_stats!.availableDrivers}",
                          Icons.check_circle_outline,
                          color: AppColors.success)),
                  SizedBox(
                      width: cardWidth,
                      child: AppComponents.statCard(
                          "Pending ride requests", "${_stats!.pendingRideRequests}", Icons.hourglass_top_outlined,
                          color: AppColors.warning)),
                  SizedBox(
                      width: cardWidth,
                      child: AppComponents.statCard(
                          "Active deliveries", "${_stats!.activeLogisticsDeliveries}", Icons.local_shipping_outlined,
                          color: AppColors.warning)),
                  SizedBox(
                      width: cardWidth,
                      child: AppComponents.statCard(
                          "Registered riders", "${_stats!.registeredRiders}", Icons.people_outline)),
                  SizedBox(
                      width: cardWidth,
                      child: AppComponents.statCard("Cash collected today", "₦${_stats!.cashCollectedToday.toStringAsFixed(0)}",
                          Icons.payments_outlined,
                          color: AppColors.success)),
                  SizedBox(
                      width: cardWidth,
                      child: AppComponents.statCard("Card revenue today", "₦${_stats!.cardRevenueToday.toStringAsFixed(0)}",
                          Icons.credit_card_outlined,
                          color: AppColors.info)),
                  SizedBox(
                      width: cardWidth,
                      child: AppComponents.statCard(
                          "RavelGo Cash revenue today", "₦${_stats!.walletRevenueToday.toStringAsFixed(0)}",
                          Icons.account_balance_wallet_outlined,
                          color: AppColors.warning)),
                ],
              );
            },
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: AppComponents.cardDecoration(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Trips this week", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 16),
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
          const SizedBox(height: 20),
          AppComponents.sectionTitle("Recent trips"),
          if (_trips.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text("No trips yet.", style: TextStyle(color: AppColors.textSecondary)),
            )
          else
            ..._trips.take(6).map((t) => Padding(
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
                              Text("${t.riderName.isEmpty ? 'Rider' : t.riderName}  →  ${t.driverName ?? 'Unassigned'}",
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                              const SizedBox(height: 4),
                              Text("${t.pickup} to ${t.destination} · ${formatFriendlyDate(t.requestedAt)}",
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary)),
                            ],
                          ),
                        ),
                        Text("₦${t.fare.toStringAsFixed(0)}", style: const TextStyle(fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                )),
        ],
      ),
    );
  }
}
