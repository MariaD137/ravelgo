import 'package:flutter/material.dart';
import 'package:ravelgo_driver_app/config/currency.dart';
import 'package:ravelgo_driver_app/services/api_client.dart';
import 'package:ravelgo_driver_app/services/driver_api.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';

/// Shown when the backend has OFFERED a REAL trip to this driver (status
/// OFFERED). Accept/Decline both call the real backend
/// (POST /trips/:id/accept | /decline) — there is no local-only acceptance;
/// the trip only becomes MATCHED once the backend says so (P0 special
/// requirement: server-authoritative accept/decline, never faked).
class IncomingRequestSheet extends StatefulWidget {
  final DriverTrip trip;
  const IncomingRequestSheet({super.key, required this.trip});

  @override
  State<IncomingRequestSheet> createState() => _IncomingRequestSheetState();
}

class _IncomingRequestSheetState extends State<IncomingRequestSheet> {
  bool _busy = false;
  String? _error;

  DriverTrip get trip => widget.trip;

  /// Display-only estimate of what the driver would earn, shown BEFORE
  /// acceptance. The trip's real `driverEarnings` is null until payment
  /// settles (long after this request is even accepted), so there is no real
  /// settled figure to show yet — this uses the trip's own `commissionRate`
  /// when the backend has already resolved one, falling back to the platform
  /// default 80%-to-driver split (DEFAULT_COMMISSION_RATE = 0.2 in
  /// backend/src/services/commission.ts) purely so the driver has a rough,
  /// clearly-labeled number to react to. This value is never stored or sent
  /// back to the backend anywhere — it is local display math only, and the
  /// backend computes and returns the authoritative split once the trip is
  /// actually paid for.
  double get _estimatedEarnings => trip.fare * (1 - (trip.commissionRate ?? 0.2));

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("New ride request", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          Row(
            children: [
              const CircleAvatar(
                  radius: 22,
                  backgroundColor: AppColors.surfaceElevated,
                  child: Icon(Icons.person, color: AppColors.textSecondary)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(trip.riderName ?? 'Rider', style: const TextStyle(fontWeight: FontWeight.w600)),
                    if (trip.riderRating != null)
                      Row(children: [
                        const Icon(Icons.star, size: 14, color: AppColors.primary),
                        const SizedBox(width: 4),
                        Text(trip.riderRating!.toStringAsFixed(1),
                            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                      ]),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _row(Icons.trip_origin, trip.pickup),
          const SizedBox(height: 8),
          _row(Icons.place_outlined, trip.destination),
          if (trip.pickupNote != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(8)),
              child: Text('Pickup note: "${trip.pickupNote}"', style: const TextStyle(fontSize: 12.5)),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                trip.distanceKm != null ? "${trip.distanceKm!.toStringAsFixed(1)} km" : "Distance —",
                style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text("Estimated earnings",
                      style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary)),
                  Text(
                    Currency.format(_estimatedEarnings, decimals: 0),
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: AppColors.danger.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8)),
              child: Text(_error!, style: const TextStyle(fontSize: 12.5, color: AppColors.danger)),
            ),
          ],
          const SizedBox(height: 20),
          if (_busy)
            const Center(child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator()))
          else if (_error != null)
            AppComponents.primaryButton(text: "OK", onPressed: () => Navigator.pop(context, null))
          else
            Row(
              children: [
                Expanded(child: AppComponents.outlineButton(text: "Decline", onPressed: _decline)),
                const SizedBox(width: 12),
                Expanded(child: AppComponents.primaryButton(text: "Accept", onPressed: _accept)),
              ],
            ),
        ],
      ),
    );
  }

  /// Calls the real backend accept endpoint (P0 special requirement — never a
  /// fabricated local acceptance). Pops with the now-MATCHED trip on success
  /// so the caller can open the live trip screen with fresh, authoritative
  /// fields; pops with null (after the user acknowledges the error) if the
  /// offer was already resolved another way (expired, declined elsewhere,
  /// or the rider cancelled).
  Future<void> _accept() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final updated = await DriverApi.acceptTrip(trip.id);
      if (mounted) Navigator.pop(context, updated);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e is ApiException ? e.message : "Could not accept this request. Please try again.";
      });
    }
  }

  /// Calls the real backend decline endpoint. This NEVER cancels the rider's
  /// trip — the backend releases the offer and re-offers it to the next
  /// eligible driver on its own.
  Future<void> _decline() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await DriverApi.declineTrip(trip.id);
      if (mounted) Navigator.pop(context, null);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e is ApiException ? e.message : "Could not decline this request. Please try again.";
      });
    }
  }

  Widget _row(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.textSecondary),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 13.5))),
      ],
    );
  }
}
