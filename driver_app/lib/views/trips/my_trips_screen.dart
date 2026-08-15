import 'package:flutter/material.dart';
import 'package:ravelgo_driver_app/models/trip.dart';
import 'package:ravelgo_driver_app/services/api_client.dart';
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
  List<Trip> _trips = [];

  @override
  void initState() {
    super.initState();
    _loadTrips();
  }

  TripStatus _parseStatus(String? status) {
    switch (status) {
      case 'COMPLETED':
        return TripStatus.completed;
      case 'CANCELLED':
        return TripStatus.cancelled;
      case 'IN_PROGRESS':
      case 'MATCHED':
      case 'REQUESTED':
        return TripStatus.inProgress;
      default:
        return TripStatus.inProgress;
    }
  }

  Trip _tripFromJson(Map<String, dynamic> json) {
    // Rider name: try nested rider object, then fall back
    String riderName = 'Rider';
    if (json['rider'] is Map) {
      final rider = json['rider'] as Map;
      final first = rider['firstName'] ?? '';
      final last = rider['lastName'] ?? '';
      riderName = '$first $last'.trim();
      if (riderName.isEmpty) riderName = 'Rider';
    }

    return Trip(
      id: json['id']?.toString() ?? '',
      riderName: riderName,
      pickup: json['pickup']?.toString() ?? '',
      destination: json['destination']?.toString() ?? '',
      fare: (json['finalFare'] ?? json['estimatedFare'] ?? 0).toDouble(),
      date: DateTime.tryParse(json['requestedAt']?.toString() ?? '') ?? DateTime.now(),
      status: _parseStatus(json['status']?.toString()),
      riderRatingGiven: json['riderRatingGiven'] != null ? (json['riderRatingGiven'] as num).toDouble() : null,
      category: json['category']?.toString() ?? 'Personal',
    );
  }

  Future<void> _loadTrips() async {
    try {
      final response = await ApiClient().get('/trips/me');
      if (!mounted) return;
      // The response may be a list directly or a paginated object with a 'data' key
      List<dynamic> tripList;
      if (response is List) {
        tripList = response;
      } else if (response is Map && response['data'] is List) {
        tripList = response['data'];
      } else {
        tripList = [];
      }
      setState(() {
        _trips = tripList.map((t) => _tripFromJson(Map<String, dynamic>.from(t))).toList();
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

  @override
  Widget build(BuildContext context) {
    final body = SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.embedded) AppComponents.sectionTitle("My Trips"),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('Failed to load trips', style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600)),
                              const SizedBox(height: 8),
                              Text(_error!, style: const TextStyle(fontSize: 12, color: Colors.black54), textAlign: TextAlign.center),
                              const SizedBox(height: 16),
                              AppComponents.outlineButton(text: "Retry", onPressed: () { setState(() { _loading = true; _error = null; }); _loadTrips(); }),
                            ],
                          ),
                        ),
                      )
                    : _trips.isEmpty
                        ? const Center(child: Text("No trips yet", style: TextStyle(color: Colors.black54)))
                        : ListView.separated(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            itemCount: _trips.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 10),
                            itemBuilder: (context, i) {
                              final t = _trips[i];
                              final cancelled = t.status == TripStatus.cancelled;
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
                                            Text(formatFriendlyDate(t.date), style: const TextStyle(fontSize: 12, color: Colors.black54)),
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
          ),
        ],
      ),
    );

    if (widget.embedded) return body;
    return Scaffold(appBar: AppBar(title: const Text("My Trips")), body: body);
  }
}
