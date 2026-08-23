import 'package:flutter/material.dart';
import 'package:ravelgo_driver_app/models/trip.dart';
import 'package:ravelgo_driver_app/services/api/api_client.dart';
import 'package:ravelgo_driver_app/services/driver_session.dart';
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
  late Future<List<Trip>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Trip>> _load() async {
    final raw = await DriverSession.instance.rideApi.getMyTrips();
    return raw.map(Trip.fromJson).toList();
  }

  void _retry() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    final body = SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.embedded) AppComponents.sectionTitle("My Trips"),
          Expanded(
            child: FutureBuilder<List<Trip>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  final message = snapshot.error is ApiException ? (snapshot.error as ApiException).message : 'Could not load your trips.';
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Colors.black54)),
                          const SizedBox(height: 12),
                          OutlinedButton(onPressed: _retry, child: const Text("Retry")),
                        ],
                      ),
                    ),
                  );
                }
                final trips = snapshot.data ?? const [];
                if (trips.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text("No trips yet — completed and cancelled rides will show up here.", style: TextStyle(color: Colors.black54)),
                    ),
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async {
                    _retry();
                    await _future;
                  },
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    itemCount: trips.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, i) {
                      final t = trips[i];
                      final cancelled = t.isCancelled;
                      return InkWell(
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TripDetailScreen(trip: t))),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: AppComponents.cardDecoration(),
                          child: Row(
                            children: [
                              Icon(cancelled ? Icons.cancel_outlined : Icons.check_circle_outline,
                                  color: cancelled ? AppColors.danger : AppColors.success),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text("${t.pickup} → ${t.destination}", style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                                    const SizedBox(height: 4),
                                    Text(formatFriendlyDate(t.requestedAt), style: const TextStyle(fontSize: 12, color: Colors.black54)),
                                  ],
                                ),
                              ),
                              Text(
                                cancelled ? "Cancelled" : "₦${t.fare.toStringAsFixed(0)}",
                                style: TextStyle(fontWeight: FontWeight.w700, color: cancelled ? AppColors.danger : Colors.black),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );

    if (widget.embedded) return body;
    return Scaffold(appBar: AppBar(title: const Text("My Trips")), body: body);
  }
}
