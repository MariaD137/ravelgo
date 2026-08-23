import 'package:flutter/material.dart';
import 'package:ravelgo_admin/models/trip_record.dart';
import 'package:ravelgo_admin/services/api/api_client.dart';
import 'package:ravelgo_admin/services/api/trip_api.dart';
import 'package:ravelgo_admin/theme/app_theme.dart';
import 'package:ravelgo_admin/utils/date_utils.dart';

class TripAdminDetailScreen extends StatefulWidget {
  final String tripId;
  final TripApi? tripApi;
  const TripAdminDetailScreen({super.key, required this.tripId, this.tripApi});

  @override
  State<TripAdminDetailScreen> createState() => _TripAdminDetailScreenState();
}

class _TripAdminDetailScreenState extends State<TripAdminDetailScreen> {
  late final TripApi _api = widget.tripApi ?? TripApi(ApiClient());
  Future<TripRecord>? _future;
  bool _mutating = false;
  bool _changed = false;

  // DISPUTED is only a legal transition from MATCHED/IN_PROGRESS/COMPLETED
  // (see backend trips.routes.ts's TRIP_ALLOWED_FROM) — matches what the
  // server will actually accept, not an invented client-side rule.
  static const _flaggable = {TripRecordStatus.matched, TripRecordStatus.inProgress, TripRecordStatus.completed};

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<TripRecord> _load() async {
    final json = await _api.getById(widget.tripId);
    return TripRecord.fromJson(json);
  }

  Future<void> _flagForReview() async {
    setState(() => _mutating = true);
    try {
      await _api.setStatus(widget.tripId, 'DISPUTED');
      _changed = true;
      if (!mounted) return;
      setState(() => _future = _load());
      await _future;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Trip flagged as disputed')));
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to flag trip: $err')));
    } finally {
      if (mounted) setState(() => _mutating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Trip')),
        body: FutureBuilder<TripRecord>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(child: Text('Failed to load trip: ${snapshot.error}'));
            }
            final trip = snapshot.data!;
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: AppComponents.cardDecoration(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _row("ID", trip.id),
                      _row("Rider", trip.riderName),
                      _row("Driver", trip.driverName),
                      _row("Pickup", trip.pickup),
                      _row("Destination", trip.destination),
                      _row("Date", formatFriendlyDate(trip.date)),
                      _row("Fare", "₦${trip.fare.toStringAsFixed(0)}"),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                if (trip.status == TripRecordStatus.disputed)
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: AppColors.danger.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
                    child: const Text(
                      "This trip is flagged as disputed. Refunds require Stripe integration, "
                      "which is not yet connected — resolve disputes manually until that lands.",
                      style: TextStyle(fontSize: 13),
                    ),
                  )
                else if (_flaggable.contains(trip.status))
                  AppComponents.outlineButton(
                    text: _mutating ? "Working…" : "Flag this trip for review",
                    onPressed: _mutating ? null : _flagForReview,
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.black54)),
          Flexible(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600), textAlign: TextAlign.right)),
        ],
      ),
    );
  }
}
