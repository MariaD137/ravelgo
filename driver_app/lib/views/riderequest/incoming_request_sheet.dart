import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ravelgo_driver_app/services/driver_session.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';

/// A real pending ride offer from the backend's Uber-style dispatch
/// (services/matching.ts): the offer is held open only until
/// `offerExpiresAt`, so this sheet shows a real countdown driven by that
/// server timestamp — purely presentational. Reaching zero only hides the
/// sheet locally (see [DriverSession.clearPendingOfferOnLocalTimeout]); it
/// never calls decline itself, since a local timeout is not the same thing
/// as the driver actually declining, and the backend's own lazy expiration
/// is what records EXPIRED. There is no backend fare-negotiation
/// capability, so the previous "Negotiate final fare" control (which only
/// updated local state and sent nothing to anyone) is gone rather than
/// kept as decoration.
class IncomingRequestSheet extends StatefulWidget {
  final Map<String, dynamic> trip;
  const IncomingRequestSheet({super.key, required this.trip});

  @override
  State<IncomingRequestSheet> createState() => _IncomingRequestSheetState();
}

class _IncomingRequestSheetState extends State<IncomingRequestSheet> {
  final DriverSession _session = DriverSession.instance;
  Timer? _countdownTimer;
  Duration _remaining = Duration.zero;

  @override
  void initState() {
    super.initState();
    _session.addListener(_onSessionChanged);
    _startCountdown();
  }

  @override
  void dispose() {
    _session.removeListener(_onSessionChanged);
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _onSessionChanged() {
    if (mounted) setState(() {});
  }

  void _startCountdown() {
    final expiresAtRaw = widget.trip['offerExpiresAt'] as String?;
    final expiresAt = expiresAtRaw != null ? DateTime.tryParse(expiresAtRaw) : null;
    if (expiresAt == null) return; // no expiry known — no countdown shown
    void tick() {
      final remaining = expiresAt.difference(DateTime.now());
      if (!mounted) return;
      setState(() => _remaining = remaining.isNegative ? Duration.zero : remaining);
      if (remaining.isNegative || remaining == Duration.zero) {
        _countdownTimer?.cancel();
        // A local timeout only hides the sheet — it must never be treated
        // as this driver declining (see class doc comment above).
        _session.clearPendingOfferOnLocalTimeout();
        Navigator.pop(context, null);
      }
    }

    tick();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) => tick());
  }

  Future<void> _accept() async {
    _countdownTimer?.cancel();
    final confirmed = await _session.acceptPendingRide();
    if (!mounted) return;
    if (confirmed == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This ride is no longer available.')),
      );
      Navigator.pop(context, null);
      return;
    }
    Navigator.pop(context, confirmed);
  }

  Future<void> _decline() async {
    _countdownTimer?.cancel();
    await _session.declinePendingRide();
    if (mounted) Navigator.pop(context, null);
  }

  @override
  Widget build(BuildContext context) {
    final trip = widget.trip;
    final rider = trip['rider'] as Map<String, dynamic>?;
    final riderName = rider != null ? '${rider['firstName']} ${rider['lastName']}' : 'Rider';
    final fare = (trip['estimatedFare'] as num?)?.toDouble() ?? 0;
    final pickupNote = trip['pickupNote'] as String?;
    final busy = _session.assignmentActionInFlight;
    final hasCountdown = trip['offerExpiresAt'] != null;
    final secondsLeft = _remaining.inSeconds;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("New ride request", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              if (hasCountdown)
                Text(
                  '${secondsLeft}s',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: secondsLeft <= 5 ? Colors.red : Colors.black54,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const CircleAvatar(radius: 22, backgroundColor: Color(0xFFF0F0F0), child: Icon(Icons.person, color: Colors.black45)),
              const SizedBox(width: 12),
              Expanded(child: Text(riderName, style: const TextStyle(fontWeight: FontWeight.w600))),
            ],
          ),
          const SizedBox(height: 16),
          _row(Icons.trip_origin, trip['pickup'] as String? ?? ''),
          const SizedBox(height: 8),
          _row(Icons.place_outlined, trip['destination'] as String? ?? ''),
          if (pickupNote != null && pickupNote.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(8)),
              child: Text('Pickup note: "$pickupNote"', style: const TextStyle(fontSize: 12.5)),
            ),
          ],
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: Text("₦${fare.toStringAsFixed(0)}", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(child: AppComponents.outlineButton(text: "Decline", onPressed: busy ? null : _decline)),
              const SizedBox(width: 12),
              Expanded(
                child: busy
                    ? const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
                    : AppComponents.primaryButton(text: "Accept", onPressed: _accept),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _row(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.black54),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 13.5))),
      ],
    );
  }
}
