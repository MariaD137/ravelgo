import 'dart:async';
import 'package:flutter/material.dart';
import 'package:ravelgo_driver_app/models/ride_request.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';

class IncomingRequestSheet extends StatefulWidget {
  final RideRequest request;
  const IncomingRequestSheet({super.key, required this.request});

  @override
  State<IncomingRequestSheet> createState() => _IncomingRequestSheetState();
}

class _IncomingRequestSheetState extends State<IncomingRequestSheet> {
  int _secondsLeft = 15;
  Timer? _timer;
  double? _counterOffer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_secondsLeft <= 1) {
        t.cancel();
        if (mounted) Navigator.pop(context, false);
      } else {
        setState(() => _secondsLeft--);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _negotiateFare() async {
    final controller = TextEditingController(text: widget.request.estimatedFare.toStringAsFixed(0));
    final result = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Propose a fare"),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(prefixText: "₦ ", border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, double.tryParse(controller.text)),
            child: const Text("Send to rider"),
          ),
        ],
      ),
    );
    if (result != null) setState(() => _counterOffer = result);
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.request;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("New ride request", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              CircleAvatar(
                radius: 16,
                backgroundColor: AppColors.primary,
                child: Text("$_secondsLeft", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const CircleAvatar(radius: 22, backgroundColor: AppColors.surfaceElevated, child: Icon(Icons.person, color: AppColors.textSecondary)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.riderName, style: const TextStyle(fontWeight: FontWeight.w600)),
                    Row(children: [
                      const Icon(Icons.star, size: 14, color: AppColors.primary),
                      const SizedBox(width: 4),
                      Text("${r.riderRating}", style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                    ]),
                  ],
                ),
              ),
              AppComponents.badge("${r.preferredLanguage}${r.quietModeRequested ? ' · Quiet mode' : ''}"),
            ],
          ),
          const SizedBox(height: 16),
          _row(Icons.trip_origin, r.pickup),
          const SizedBox(height: 8),
          _row(Icons.place_outlined, r.destination),
          if (r.pickupNote != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(8)),
              child: Text('Pickup note: "${r.pickupNote}"', style: const TextStyle(fontSize: 12.5)),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("${r.distanceKm} km · ${r.etaMinutes} min away", style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
              Text(
                _counterOffer != null ? "₦${_counterOffer!.toStringAsFixed(0)} (proposed)" : "₦${r.estimatedFare.toStringAsFixed(0)}",
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(child: AppComponents.outlineButton(text: "Decline", onPressed: () => Navigator.pop(context, false))),
              const SizedBox(width: 12),
              Expanded(child: AppComponents.primaryButton(text: "Accept", onPressed: () => Navigator.pop(context, true))),
            ],
          ),
          const SizedBox(height: 10),
          Center(
            child: TextButton(onPressed: _negotiateFare, child: const Text("Negotiate final fare")),
          ),
        ],
      ),
    );
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
