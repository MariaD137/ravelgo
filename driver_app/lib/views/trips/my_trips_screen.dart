import 'package:flutter/material.dart';
import 'package:ravelgo_driver_app/config/currency.dart';
import 'package:ravelgo_driver_app/services/api_client.dart';
import 'package:ravelgo_driver_app/services/driver_api.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';
import 'package:ravelgo_driver_app/utils/date_utils.dart';
import 'package:ravelgo_driver_app/views/trips/trip_detail_screen.dart';

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
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return _empty(Icons.cloud_off, "Couldn't load trips", _error!, showRetry: true);
    }
    if (_trips.isEmpty) {
      return _empty(Icons.local_taxi_outlined, "No trips yet",
          "Go online from the Home tab to start receiving trips.");
    }
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
              await Navigator.push(context, MaterialPageRoute(builder: (_) => TripDetailScreen(trip: t)));
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

  Widget _empty(IconData icon, String title, String subtitle, {bool showRetry = false}) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 100),
        Icon(icon, size: 56, color: AppColors.textMuted),
        const SizedBox(height: 16),
        Center(child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600))),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSecondary)),
        ),
        if (showRetry)
          Center(child: TextButton(onPressed: _load, child: const Text("Try again"))),
      ],
    );
  }
}
