import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ravelgo_driver_app/config/currency.dart';
import 'package:geolocator/geolocator.dart';
import 'package:ravelgo_driver_app/services/api_client.dart';
import 'package:ravelgo_driver_app/services/driver_api.dart';
import 'package:ravelgo_driver_app/services/realtime_service.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';
import 'package:ravelgo_driver_app/utils/date_utils.dart';

class TripDetailScreen extends StatefulWidget {
  final DriverTrip trip;
  const TripDetailScreen({super.key, required this.trip});

  @override
  State<TripDetailScreen> createState() => _TripDetailScreenState();
}

class _TripDetailScreenState extends State<TripDetailScreen> {
  late DriverTrip _trip = widget.trip;
  bool _busy = false;

  // Live location streaming while the trip is in progress.
  final RealtimeService _rt = RealtimeService();
  Timer? _locTimer;
  bool _streaming = false;

  bool get _cancelled => _trip.status == 'CANCELLED' || _trip.status == 'DISPUTED';

  @override
  void initState() {
    super.initState();
    _syncStreaming();
  }

  @override
  void dispose() {
    _stopStreaming();
    super.dispose();
  }

  /// Start streaming location once the trip is IN_PROGRESS; stop otherwise.
  Future<void> _syncStreaming() async {
    if (_trip.status == 'IN_PROGRESS' && !_streaming) {
      if (!RealtimeService.isConfigured) return;
      final ok = await _rt.connect();
      if (!ok) return;
      _streaming = true;
      // Push an immediate fix, then every 5 seconds while on the trip.
      _pushLocation();
      _locTimer = Timer.periodic(const Duration(seconds: 5), (_) => _pushLocation());
    } else if (_trip.status != 'IN_PROGRESS' && _streaming) {
      _stopStreaming();
    }
  }

  void _stopStreaming() {
    _locTimer?.cancel();
    _locTimer = null;
    if (_streaming) _rt.dispose();
    _streaming = false;
  }

  Future<void> _pushLocation() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return;
      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      _rt.sendLocation(pos.latitude, pos.longitude);
    } catch (_) {
      // Best-effort: a failed fix just means no update this tick.
    }
  }

  Color _statusColor() {
    if (_cancelled) return AppColors.danger;
    if (_trip.status == 'COMPLETED') return AppColors.success;
    return AppColors.primaryDark;
  }

  String _pretty(String s) => s.isEmpty ? '' : s[0] + s.substring(1).toLowerCase().replaceAll('_', ' ');

  Future<void> _advance(String toStatus, {double? finalFare}) async {
    setState(() => _busy = true);
    try {
      final updated = await DriverApi.updateTripStatus(_trip.id, toStatus, finalFare: finalFare);
      if (!mounted) return;
      setState(() => _trip = updated);
      _syncStreaming(); // start pushing location when IN_PROGRESS, stop when done
    } catch (e) {
      if (!mounted) return;
      final msg = e is ApiException ? e.message : e.toString();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('#${_trip.id.substring(0, _trip.id.length < 6 ? _trip.id.length : 6)}')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppComponents.badge(_pretty(_trip.status), color: _statusColor()),
            const SizedBox(height: 12),
            Text(formatFriendlyDate(_trip.requestedAt), style: const TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: AppComponents.cardDecoration(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _row(Icons.trip_origin, _trip.pickup),
                  const SizedBox(height: 10),
                  _row(Icons.place_outlined, _trip.destination),
                  AppComponents.divider(),
                  if (_trip.riderName != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text("Rider"),
                          Text(_trip.riderName!, style: const TextStyle(fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  const SizedBox(height: 8),
                  ..._earningsRows(),
                ],
              ),
            ),
            const SizedBox(height: 20),
            ..._actions(),
          ],
        ),
      ),
    );
  }

  List<Widget> _actions() {
    if (_busy) {
      return const [Center(child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator()))];
    }
    switch (_trip.status) {
      case 'MATCHED':
        return [
          AppComponents.primaryButton(text: "Start trip", onPressed: () => _advance('IN_PROGRESS')),
        ];
      case 'IN_PROGRESS':
        return [
          AppComponents.primaryButton(
            text: "Complete trip",
            // Charge the agreed estimate (1.0x is within the allowed fare band).
            onPressed: () => _advance('COMPLETED', finalFare: _trip.estimatedFare),
          ),
        ];
      default:
        return [
          AppComponents.outlineButton(
            text: "Download receipt",
            onPressed: () =>
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Receipt saved to device"))),
          ),
        ];
    }
  }

  /// The commission breakdown, or the plain fare — never a computed guess.
  ///
  /// `driverEarnings`/`platformCommission` come straight from the backend
  /// (trip-view.ts) and are null until this trip's payment actually settles.
  /// Until then there is no real split to show, so this falls back to the
  /// single fare row exactly as before rather than inventing one.
  List<Widget> _earningsRows() {
    final t = _trip;
    if (t.driverEarnings == null) {
      return [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text("Fare", style: TextStyle(fontWeight: FontWeight.w700)),
            Text(Currency.format(t.fare), style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
        if (t.status == 'COMPLETED') ...[
          const SizedBox(height: 4),
          const Text("Payment pending — earnings will show once it settles.",
              style: TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
        ],
      ];
    }

    final commission = t.platformCommission ?? 0;
    // Reconstructs the exact gross that was commissioned (finalFare) from the
    // backend's own split — never a value this app computed independently.
    final grossFare = t.driverEarnings! + commission;
    final pct = t.commissionRate != null ? ' (${(t.commissionRate! * 100).round()}%)' : '';

    return [
      _earningsRow("Customer paid", Currency.format(grossFare)),
      if (commission > 0) _earningsRow("RavelGo commission$pct", '-${Currency.format(commission)}', muted: true),
      if (t.waitingCharge != null && t.waitingCharge! > 0)
        _earningsRow("Waiting charge", '+${Currency.format(t.waitingCharge!)}', accent: AppColors.success),
      if (t.cancellationFee != null && t.cancellationFee! > 0)
        _earningsRow("Cancellation fee", '+${Currency.format(t.cancellationFee!)}', accent: AppColors.success),
      AppComponents.divider(),
      const SizedBox(height: 4),
      _earningsRow("Your earnings", Currency.format(t.driverEarnings!), bold: true),
    ];
  }

  Widget _earningsRow(String label, String value, {bool bold = false, bool muted = false, Color? accent}) {
    final color = accent ?? (muted ? AppColors.textSecondary : null);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(fontWeight: bold ? FontWeight.w700 : FontWeight.w500, color: color)),
          Text(value,
              style: TextStyle(fontWeight: bold ? FontWeight.w700 : FontWeight.w500, color: color)),
        ],
      ),
    );
  }

  Widget _row(IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: AppColors.textSecondary),
        const SizedBox(width: 8),
        Expanded(child: Text(text)),
      ],
    );
  }
}
