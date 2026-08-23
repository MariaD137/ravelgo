import 'package:flutter/material.dart';
import 'package:ravelgo_driver_app/services/driver_session.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';

/// A real ride the backend already matched to this driver (services/
/// matching.ts, synchronous and server-side) — there is no "offer" the
/// driver could lose to another driver by taking too long, so this sheet
/// no longer has a countdown timer that auto-declines. There is also no
/// backend fare-negotiation capability, so the previous "Negotiate final
/// fare" control (which only updated local state and sent nothing to
/// anyone) is gone rather than kept as decoration.
class IncomingRequestSheet extends StatefulWidget {
  final Map<String, dynamic> trip;
  const IncomingRequestSheet({super.key, required this.trip});

  @override
  State<IncomingRequestSheet> createState() => _IncomingRequestSheetState();
}

class _IncomingRequestSheetState extends State<IncomingRequestSheet> {
  final DriverSession _session = DriverSession.instance;

  @override
  void initState() {
    super.initState();
    _session.addListener(_onSessionChanged);
  }

  @override
  void dispose() {
    _session.removeListener(_onSessionChanged);
    super.dispose();
  }

  void _onSessionChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _accept() async {
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

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("New ride request", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
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
