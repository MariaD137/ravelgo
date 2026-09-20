import 'package:flutter/material.dart';
import 'package:ravelgo_driver_app/config/currency.dart';
import 'package:ravelgo_driver_app/services/api_client.dart';
import 'package:ravelgo_driver_app/services/driver_api.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';
import 'package:ravelgo_driver_app/utils/date_utils.dart';
import 'package:ravelgo_driver_app/views/trips/trip_detail_screen.dart';
import 'package:ravelgo_driver_app/widgets/app_page_route.dart';
import 'package:ravelgo_driver_app/widgets/empty_state.dart';
import 'package:ravelgo_driver_app/widgets/shimmer.dart';

class MyTripsScreen extends StatefulWidget {
  final bool embedded;
  const MyTripsScreen({super.key, this.embedded = false});

  @override
  State<MyTripsScreen> createState() => _MyTripsScreenState();
}

class _MyTripsScreenState extends State<MyTripsScreen> {
  bool _loading = true;
  String? _error;
  List<DriverTrip> _trips = const [];

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
      final trips = await DriverApi.myTrips();
      if (!mounted) return;
      setState(() {
        _trips = trips;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = describeApiFailure(e, what: 'your trips');
        _loading = false;
      });
    }
  }

  Color _statusColor(String s) {
    switch (s) {
      case 'COMPLETED':
        return AppColors.success;
      case 'CANCELLED':
      case 'DISPUTED':
        return AppColors.danger;
      case 'IN_PROGRESS':
      case 'MATCHED':
        return AppColors.primaryDark;
      default:
        return AppColors.textSecondary;
    }
  }

  String _pretty(String s) => s.isEmpty ? '' : s[0] + s.substring(1).toLowerCase().replaceAll('_', ' ');

  @override
  Widget build(BuildContext context) {
    final body = SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (widget.embedded) Expanded(child: AppComponents.sectionTitle("My Trips")),
              IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh)),
            ],
          ),
          Expanded(child: _list()),
        ],
      ),
    );

    if (widget.embedded) return body;
    return Scaffold(appBar: AppBar(title: const Text("My Trips")), body: body);
  }

  Widget _list() {
    return AsyncBody(
      stateKey: _loading ? "loading" : (_error != null ? "error" : "data:${_trips.length}"),
      child: _loading
          ? const ShimmerList()
          : _error != null
              ? EmptyState(
                  icon: Icons.cloud_off,
                  title: "Couldn't load trips",
                  subtitle: _error!,
                  onRetry: _load,
                )
              : _trips.isEmpty
                  ? const EmptyState(
                      icon: Icons.local_taxi_outlined,
                      title: "No trips yet",
                      subtitle: "Go online from the Home tab to start receiving trips.",
                    )
                  : _tripList(),
    );
  }

  Widget _tripList() {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _trips.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          final t = _trips[i];
          return InkWell(
            onTap: () async {
              await Navigator.push(context, AppPageRoute(builder: (_) => TripDetailScreen(trip: t)));
              _load(); // reflect any status change made on the detail screen
            },
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: AppComponents.cardDecoration(),
              child: Row(
                children: [
                  Icon(Icons.directions_car, color: _statusColor(t.status)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("${t.pickup} → ${t.destination}",
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                        const SizedBox(height: 4),
                        Text("${formatFriendlyDate(t.requestedAt)} · ${_pretty(t.status)}",
                            style: TextStyle(fontSize: 12, color: _statusColor(t.status))),
                      ],
                    ),
                  ),
                  Text(Currency.format(t.fare),
                      style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

}
