import 'package:flutter/material.dart';
import 'package:ravelgo_driver_app/models/driver_profile.dart';
import 'package:ravelgo_driver_app/services/api_client.dart';
import 'package:ravelgo_driver_app/services/driver_api.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';
import 'package:ravelgo_driver_app/utils/date_utils.dart';
import 'package:ravelgo_driver_app/widgets/shimmer.dart';

/// The driver's real rating and rider feedback — GET /api/drivers/me (via
/// [profile], already loaded by the caller) for the headline average, and
/// GET /api/trips/mine for the per-trip stars/comments a rider actually left
/// (POST /trips/:id/rating). Nothing here is fabricated: a trip with no
/// rating yet is simply not in this list, and a rating with no comment says
/// so instead of inventing review text.
class MyRatingsScreen extends StatefulWidget {
  final DriverProfile profile;
  const MyRatingsScreen({super.key, this.profile = const DriverProfile()});

  @override
  State<MyRatingsScreen> createState() => _MyRatingsScreenState();
}

class _MyRatingsScreenState extends State<MyRatingsScreen> {
  bool _loading = true;
  String? _error;
  List<DriverTrip> _rated = const [];

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
      final rated = trips.where((t) => t.riderRating != null).toList()
        ..sort((a, b) => (b.completedAt ?? b.requestedAt).compareTo(a.completedAt ?? a.requestedAt));
      setState(() {
        _rated = rated;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = describeApiFailure(e, what: 'your ratings');
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("My Ratings")),
      body: RefreshIndicator(onRefresh: _load, child: _body()),
    );
  }

  Widget _body() {
    if (_loading) {
      return const ShimmerDetail();
    }
    return ListView(
      padding: const EdgeInsets.all(20),
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        if (_error != null)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: AppComponents.cardDecoration(),
            child: Column(children: [
              Text(_error!, style: const TextStyle(color: AppColors.danger)),
              TextButton(onPressed: _load, child: const Text('Try again')),
            ]),
          ),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: AppComponents.cardDecoration(),
          child: Column(
            children: [
              Text(widget.profile.rating.toStringAsFixed(1), style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold)),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (i) {
                  final filled = i < widget.profile.rating.round();
                  return Icon(filled ? Icons.star : Icons.star_border, color: AppColors.primaryDark, size: 18);
                }),
              ),
              const SizedBox(height: 4),
              Text("Based on ${widget.profile.totalTrips} trips", style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        AppComponents.sectionTitle("Rider feedback"),
        if (!_loading && _error == null && _rated.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Text(
              "No rider has left feedback yet. It'll show up here after your next completed trip.",
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
          ),
        ..._rated.map((t) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: AppComponents.cardDecoration(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        ...List.generate(t.riderRating!.round(), (i) => const Icon(Icons.star, size: 14, color: AppColors.primaryDark)),
                        ...List.generate(5 - t.riderRating!.round(), (i) => const Icon(Icons.star_border, size: 14, color: AppColors.textMuted)),
                        const Spacer(),
                        Text(
                          formatFriendlyDate(t.completedAt ?? t.requestedAt),
                          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      (t.riderComment?.isNotEmpty ?? false) ? t.riderComment! : 'No comment left',
                      style: TextStyle(
                        fontSize: 13,
                        color: (t.riderComment?.isNotEmpty ?? false) ? null : AppColors.textMuted,
                        fontStyle: (t.riderComment?.isNotEmpty ?? false) ? FontStyle.normal : FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
            )),
      ],
    );
  }
}
