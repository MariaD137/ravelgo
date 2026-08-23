import 'package:flutter/material.dart';
import 'package:ravelgo_rider_app/services/api/api_client.dart';
import 'package:ravelgo_rider_app/services/api/ride_api.dart';
import 'package:ravelgo_rider_app/views/RideView/RideDetailsView.dart';

const _monthNames = [
  '',
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

String formatTripTime(DateTime dt) {
  final local = dt.toLocal();
  final months = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final minute = local.minute.toString().padLeft(2, '0');
  final ampm = local.hour >= 12 ? 'pm' : 'am';
  return '${local.day} ${months[local.month]}. $hour:$minute $ampm';
}

/// The rider's real trip history — GET /api/trips/mine, most recent first.
/// Each row is a real Trip row (pickup/destination/status/fare/timestamp),
/// not a hardcoded sample.
class RidesView extends StatefulWidget {
  RidesView({super.key, RideApi? rideApi}) : rideApi = rideApi ?? RideApi(ApiClient());

  final RideApi rideApi;

  @override
  State<RidesView> createState() => _RidesViewState();
}

class _RidesViewState extends State<RidesView> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.rideApi.myTrips();
  }

  Future<void> _refresh() async {
    final future = widget.rideApi.myTrips();
    setState(() => _future = future);
    await future;
  }

  Map<String, List<Map<String, dynamic>>> _groupByMonth(List<Map<String, dynamic>> trips) {
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final trip in trips) {
      final requestedAt = DateTime.tryParse(trip['requestedAt'] as String? ?? '')?.toLocal();
      final key = requestedAt == null ? 'Unknown date' : '${_monthNames[requestedAt.month]} ${requestedAt.year}';
      grouped.putIfAbsent(key, () => []).add(trip);
    }
    return grouped;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8),
              child: Row(
                children: [
                  IconButton(icon: const Icon(Icons.close, size: 24), onPressed: () => Navigator.of(context).pop()),
                  const Expanded(
                    child: Center(
                      child: Text('Ride history', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refresh,
                child: FutureBuilder<List<Map<String, dynamic>>>(
                  future: _future,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          const SizedBox(height: 80),
                          Center(child: Text('Failed to load: ${snapshot.error}', textAlign: TextAlign.center)),
                          const SizedBox(height: 12),
                          Center(child: TextButton(onPressed: _refresh, child: const Text('Retry'))),
                        ],
                      );
                    }
                    final trips = snapshot.data ?? const [];
                    if (trips.isEmpty) {
                      return ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: const [
                          SizedBox(height: 100),
                          Center(child: Text('No rides yet', style: TextStyle(color: Colors.black54))),
                        ],
                      );
                    }
                    final grouped = _groupByMonth(trips);
                    final children = <Widget>[];
                    grouped.forEach((month, monthTrips) {
                      children.add(Padding(
                        padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
                        child: Text(month, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                      ));
                      for (final trip in monthTrips) {
                        final requestedAt = DateTime.tryParse(trip['requestedAt'] as String? ?? '');
                        final fare = (trip['finalFare'] as num?) ?? (trip['estimatedFare'] as num?);
                        children.add(Column(
                          children: [
                            ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              leading: Container(
                                width: 46,
                                height: 46,
                                decoration:
                                    BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(8)),
                                child: Icon(Icons.directions_car, color: Colors.grey.shade700),
                              ),
                              title: Text(
                                trip['destination'] as String? ?? 'Trip',
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 6.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      requestedAt != null ? formatTripTime(requestedAt) : (trip['status'] as String? ?? ''),
                                      style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      fare != null ? '₦${fare.toStringAsFixed(0)} · ${trip['status']}' : '${trip['status']}',
                                      style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                                    ),
                                  ],
                                ),
                              ),
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(builder: (_) => RideDetailsScreen(trip: trip)),
                                );
                              },
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16.0),
                              child: Divider(height: 1, color: Colors.grey.shade300),
                            ),
                          ],
                        ));
                      }
                    });
                    return ListView(physics: const AlwaysScrollableScrollPhysics(), children: children);
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
