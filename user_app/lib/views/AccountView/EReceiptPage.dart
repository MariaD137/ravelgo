import 'package:flutter/material.dart';
import 'package:ravelgo_user_app/config/currency.dart';
import 'package:ravelgo_user_app/services/rider_api.dart';
import 'package:ravelgo_user_app/services/trips_api.dart';
import 'package:ravelgo_user_app/theme/app_theme.dart';
import 'package:ravelgo_user_app/views/RideView/RidesView.dart';
import 'package:share_plus/share_plus.dart';

/// A real receipt for one completed ride.
///
/// Every value shown here comes from the backend — the [Ride] passed in (real
/// data already fetched for the ride-history list) for the fields always
/// available, plus a fetch of the full trip detail (GET /api/trips/:id, which
/// is the only trip route that includes real payment method/status/amount)
/// for the rest. Nothing is fabricated: a field the backend hasn't populated
/// yet (e.g. the trip hasn't been charged) renders as "Not available" rather
/// than a guessed value, and the screen stays usable even if the detail fetch
/// fails outright — it just falls back to what [ride] already had.
class EReceiptPage extends StatefulWidget {
  final Ride ride;
  const EReceiptPage({super.key, required this.ride});

  @override
  State<EReceiptPage> createState() => _EReceiptPageState();
}

class _EReceiptPageState extends State<EReceiptPage> {
  bool _loading = true;
  Trip? _detail;
  String? _customerName;
  String? _customerPhone;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    Trip? detail;
    Map<String, dynamic>? me;
    try {
      detail = await TripsApi.byId(widget.ride.tripId);
    } catch (_) {
      // Non-fatal: the receipt still renders from widget.ride below.
    }
    try {
      me = await RiderApi.getMe();
    } catch (_) {
      // Non-fatal: the receipt still renders without the account name.
    }
    if (!mounted) return;
    final name = me == null
        ? null
        : [me['firstName'], me['lastName']]
            .where((e) => e != null && '$e'.trim().isNotEmpty)
            .join(' ')
            .trim();
    setState(() {
      _detail = detail;
      _customerName = (name == null || name.isEmpty) ? null : name;
      _customerPhone = me?['phoneNumber']?.toString();
      _loading = false;
    });
  }

  String _formatDateTime(DateTime dt) {
    const months = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final minute = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return '${dt.day} ${months[dt.month]} ${dt.year} | $hour:$minute $ampm';
  }

  String _prettyMethod(String? method) {
    switch (method) {
      case 'CARD':
        return 'Card';
      case 'WALLET':
        return 'RavelGo Cash';
      case 'CASH':
        return 'Cash';
      default:
        return 'Not available';
    }
  }

  String _prettyStatus(String? status) {
    switch (status) {
      case 'SUCCEEDED':
        return 'Paid';
      case 'PENDING':
        return 'Pending';
      case 'FAILED':
        return 'Failed';
      case 'REFUNDED':
        return 'Refunded';
      default:
        return 'Not yet paid';
    }
  }

  @override
  Widget build(BuildContext context) {
    final ride = widget.ride;
    final detail = _detail;
    // The final, authoritative total once the trip has been charged; the
    // ride-list estimate otherwise — never recomputed on the client.
    final total = detail?.finalFare ?? detail?.estimatedFare ?? ride.fare;
    final transactionId = detail?.paymentId ?? ride.tripId;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(Icons.arrow_back),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    "E - Receipt",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            if (_loading)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      Container(
                        height: 80,
                        width: double.infinity,
                        color: AppColors.surface,
                        child: const Center(
                          child: Text("|||||||||||||||||||||||||||||", style: TextStyle(letterSpacing: 2)),
                        ),
                      ),
                      const SizedBox(height: 16),
                      _card([
                        _row("Trip", ride.title),
                        _row("Pickup", ride.pickup.isNotEmpty ? ride.pickup : 'Not available'),
                        _row("Destination", ride.destination.isNotEmpty ? ride.destination : 'Not available'),
                        _row("Date", _formatDateTime(ride.dateTime)),
                        if (detail?.distanceKm != null) _row("Distance", '${detail!.distanceKm!.toStringAsFixed(1)} km'),
                        if (ride.driverName != null && ride.driverName!.isNotEmpty) _row("Driver", ride.driverName!),
                        _row("Total", Currency.format(total, decimals: 0)),
                      ]),
                      const SizedBox(height: 16),
                      _card([
                        _row("Name", _customerName ?? 'Not available'),
                        if (_customerPhone != null && _customerPhone!.isNotEmpty) _row("Phone Number", _customerPhone!),
                        _row("Payment Method", _prettyMethod(detail?.paymentMethod)),
                        _row("Payment Status", _prettyStatus(detail?.paymentStatus)),
                        if (detail?.paidAt != null) _row("Paid At", _formatDateTime(detail!.paidAt!)),
                        _row("Transaction ID", transactionId),
                      ]),
                    ],
                  ),
                ),
              ),
            _bottomButton(
              "Download E-receipt",
              _loading ? null : () => _download(ride, detail, total, transactionId),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _download(
    Ride ride,
    Trip? detail,
    double total,
    String transactionId,
  ) async {
    // No server-side PDF/export endpoint exists (backend
    // GET /api/payments/:id/receipt returns JSON, not a file) — this hands
    // the exact same real values shown on screen to the OS share sheet
    // (share_plus, already used elsewhere in this app — see
    // invite_a_friend.dart), which lets the user save or forward it as a
    // real file rather than the previous no-op button.
    final text = StringBuffer()
      ..writeln('RavelGo — Ride Receipt')
      ..writeln('Trip: ${ride.title}')
      ..writeln('Pickup: ${ride.pickup}')
      ..writeln('Destination: ${ride.destination}')
      ..writeln('Date: ${_formatDateTime(ride.dateTime)}')
      ..writeln('Total: ${Currency.format(total, decimals: 0)}')
      ..writeln('Payment Method: ${_prettyMethod(detail?.paymentMethod)}')
      ..writeln('Payment Status: ${_prettyStatus(detail?.paymentStatus)}')
      ..writeln('Transaction ID: $transactionId');

    await SharePlus.instance.share(ShareParams(text: text.toString(), subject: 'RavelGo Ride Receipt'));
  }

  Widget _card(List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: children.map((e) => Column(children: [e, const Divider(height: 20)])).toList()..removeLast(),
      ),
    );
  }

  Widget _row(String title, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: Text(title, style: const TextStyle(color: AppColors.textSecondary))),
        Flexible(
          flex: 2,
          child: Text(value, textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }

  Widget _bottomButton(String text, VoidCallback? onTap) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        boxShadow: [BoxShadow(color: AppColors.border, blurRadius: 10)],
      ),
      child: SizedBox(
        width: double.infinity,
        height: 48,
        child: ElevatedButton(
          onPressed: onTap,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: Text(text),
        ),
      ),
    );
  }
}
