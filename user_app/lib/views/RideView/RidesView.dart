import 'package:flutter/material.dart';
import 'package:ravelgo_user_app/config/currency.dart';
import 'package:ravelgo_user_app/services/api_client.dart';
import 'package:ravelgo_user_app/services/trips_api.dart';
import 'package:ravelgo_user_app/views/RideView/RideDetailsView.dart';
import 'package:ravelgo_user_app/theme/app_theme.dart';

/// View-model for a single row in the ride history, built from a backend [Trip].
class Ride {
  final DateTime dateTime;
  final String title;
  final String id;
  final String pickup;
  final String destination;
  final double fare;
  final String status;
  final String? driverName;

  Ride({
    required this.dateTime,
    required this.title,
    required this.id,
    this.pickup = '',
    this.destination = '',
    this.fare = 0,
    this.status = '',
    this.driverName,
  });

  factory Ride.fromTrip(Trip t) => Ride(
        dateTime: t.requestedAt,
        title: t.destination.isNotEmpty ? t.destination : 'Trip',
        id: '#${t.id.substring(0, t.id.length < 6 ? t.id.length : 6)}',
        pickup: t.pickup,
        destination: t.destination,
        fare: t.fare,
        status: t.status,
        driverName: t.driverName,
      );
}

class RidesView extends StatefulWidget {
  const RidesView({Key? key}) : super(key: key);

  @override
  State<RidesView> createState() => _RidesViewState();
}

class _RidesViewState extends State<RidesView> {
  static const _months = [
    '', 'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  bool _loading = true;
  String? _error;
  Map<String, List<Ride>> _ridesByMonth = {};

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
      final trips = await TripsApi.mine();
      final grouped = <String, List<Ride>>{};
      for (final t in trips) {
        final ride = Ride.fromTrip(t);
        final key = '${_months[ride.dateTime.month]} ${ride.dateTime.year}';
        grouped.putIfAbsent(key, () => []).add(ride);
      }
      if (!mounted) return;
      setState(() {
        _ridesByMonth = grouped;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException && e.statusCode == 403
            ? 'Your account isn\'t set up as a rider yet.'
            : e.toString();
        _loading = false;
      });
    }
  }

  String _formatTime(DateTime dt) {
    const m = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final minute = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'pm' : 'am';
    return '${dt.day} ${m[dt.month]}. $hour:$minute $ampm';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8),
              child: Row(
                children: [
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Center(
                      child: Text('Ride history',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 24),
                    onPressed: _loading ? null : _load,
                  ),
                ],
              ),
            ),
            Expanded(child: _body()),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return _centered(
        icon: Icons.cloud_off,
        title: 'Couldn\'t load your rides',
        subtitle: _error!,
        action: TextButton(onPressed: _load, child: const Text('Try again')),
      );
    }
    if (_ridesByMonth.isEmpty) {
      return _centered(
        icon: Icons.directions_car_outlined,
        title: 'No rides yet',
        subtitle: 'Your completed and upcoming rides will show up here.',
      );
    }

    final children = <Widget>[];
    _ridesByMonth.forEach((month, rides) {
      children.add(Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
        child: Text(month, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
      ));
      for (final ride in rides) {
        children.add(Column(
          children: [
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              leading: Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: AppColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.directions_car, color: AppColors.textSecondary),
              ),
              title: Text(ride.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 6.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_formatTime(ride.dateTime),
                        style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Text(ride.id, style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                        const Spacer(),
                        if (ride.status.isNotEmpty)
                          Text(_prettyStatus(ride.status),
                              style: TextStyle(fontSize: 12, color: _statusColor(ride.status), fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ],
                ),
              ),
              trailing: Text(Currency.format(ride.fare),
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => RideDetailsScreen(ride: ride)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Divider(height: 1, color: AppColors.border),
            ),
          ],
        ));
      }
    });

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(physics: const AlwaysScrollableScrollPhysics(), children: children),
    );
  }

  String _prettyStatus(String s) =>
      s.isEmpty ? '' : s[0] + s.substring(1).toLowerCase().replaceAll('_', ' ');

  Color _statusColor(String s) {
    switch (s) {
      case 'COMPLETED':
        return AppColors.success;
      case 'CANCELLED':
      case 'DISPUTED':
        return AppColors.error;
      default:
        return AppColors.primary;
    }
  }

  Widget _centered({required IconData icon, required String title, required String subtitle, Widget? action}) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 120),
        Center(child: Icon(icon, size: 56, color: AppColors.textMuted)),
        const SizedBox(height: 16),
        Center(child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600))),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Text(subtitle, textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondary)),
        ),
        if (action != null) Center(child: action),
      ],
    );
  }
}
