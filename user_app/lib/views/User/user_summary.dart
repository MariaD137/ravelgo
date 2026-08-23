import 'package:flutter/material.dart';
import 'package:ravelgo_rider_app/services/api/api_client.dart';
import 'package:ravelgo_rider_app/services/api/ride_api.dart';
import 'package:ravelgo_rider_app/services/api/rider_api.dart';
import 'package:ravelgo_rider_app/views/bottommenu/BottomNavigationView.dart';

/// A real name (GET /api/riders/me) and a real completed-trip count
/// (GET /api/trips/mine). There is no rider "rating"/"acceptance rate" in
/// this schema — those are Driver-only fields — so the previous fixed
/// "4.55 Rating" line and two "Acceptance rate" cards (which never showed
/// any number at all) are gone rather than kept as decoration with no
/// data behind them.
class UserSummary extends StatefulWidget {
  UserSummary({super.key, RiderApi? riderApi, RideApi? rideApi})
    : riderApi = riderApi ?? RiderApi(ApiClient()),
      rideApi = rideApi ?? RideApi(ApiClient());

  final RiderApi riderApi;
  final RideApi rideApi;

  @override
  State<UserSummary> createState() => _UserSummaryState();
}

class _UserSummaryState extends State<UserSummary> {
  late Future<(Map<String, dynamic>?, int)> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<(Map<String, dynamic>?, int)> _load() async {
    Map<String, dynamic>? rider;
    try {
      rider = await widget.riderApi.getMe();
    } on ApiException catch (err) {
      if (err.statusCode != 404) rethrow;
    }
    final trips = await widget.rideApi.myTrips();
    return (rider, trips.length);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: FutureBuilder<(Map<String, dynamic>?, int)>(
            future: _future,
            builder: (context, snapshot) {
              final rider = snapshot.data?.$1;
              final tripCount = snapshot.data?.$2;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back_ios)),
                  ),
                  const SizedBox(height: 20),
                  const CircleAvatar(radius: 30, backgroundColor: Colors.grey, child: Icon(Icons.person, color: Colors.white)),
                  const SizedBox(height: 16),
                  Text(
                    rider != null
                        ? '${rider['firstName']} ${rider['lastName']}'
                        : (snapshot.connectionState == ConnectionState.waiting ? 'Loading…' : 'Rider'),
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 40),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 140,
                        child: SummaryCard(title: "Total trips", value: tripCount?.toString() ?? '—'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 30),
                  GestureDetector(
                    onTap: () {
                      Navigator.pop(context);
                      BottomNavigationView.globalKey.currentState?.changeTab(3);
                    },
                    child: const Text(
                      "View more details",
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, decoration: TextDecoration.underline),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class SummaryCard extends StatelessWidget {
  final String title;
  final String value;

  const SummaryCard({Key? key, required this.title, required this.value}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE8C75F)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal)),
        ],
      ),
    );
  }
}
