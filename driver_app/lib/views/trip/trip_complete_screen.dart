import 'package:flutter/material.dart';
import 'package:ravelgo_driver_app/config/currency.dart';
import 'package:ravelgo_driver_app/services/driver_api.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';
import 'package:ravelgo_driver_app/views/shell/driver_shell.dart';

class TripCompleteScreen extends StatefulWidget {
  final DriverTrip trip;
  const TripCompleteScreen({super.key, required this.trip});

  @override
  State<TripCompleteScreen> createState() => _TripCompleteScreenState();
}

class _TripCompleteScreenState extends State<TripCompleteScreen> {
  int _rating = 0;

  @override
  Widget build(BuildContext context) {
    // The backend has finalized the trip; use its real fare. The service-fee
    // line mirrors the backend's 25% platform commission (PLATFORM_COMMISSION_RATE)
    // and is labelled as an estimate — the authoritative amount is the payout the
    // backend generates from completed trips.
    final fare = widget.trip.fare;
    final platformFee = fare * 0.25;
    final earnings = fare - platformFee;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.check_circle, color: AppColors.success, size: 56),
              const SizedBox(height: 12),
              const Text("Trip completed", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: AppComponents.cardDecoration(),
                child: Column(
                  children: [
                    _fareRow("Trip fare", Currency.format(fare, decimals: 0)),
                    _fareRow("RavelGo service fee", "- ${Currency.format(platformFee, decimals: 0)}"),
                    AppComponents.divider(),
                    _fareRow("Estimated earnings", Currency.format(earnings, decimals: 0), bold: true),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              const Text("Rate your rider", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              const Text("Your rating is anonymous and helps keep RavelGo safe", style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              const SizedBox(height: 12),
              Row(
                children: List.generate(5, (i) {
                  final filled = i < _rating;
                  return IconButton(
                    onPressed: () => setState(() => _rating = i + 1),
                    icon: Icon(filled ? Icons.star : Icons.star_border, color: AppColors.primaryDark, size: 32),
                  );
                }),
              ),
              const Spacer(),
              AppComponents.primaryButton(
                text: "Done",
                onPressed: () {
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const DriverShell()),
                    (route) => false,
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fareRow(String label, String value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 14, fontWeight: bold ? FontWeight.w700 : FontWeight.normal)),
          Text(value, style: TextStyle(fontSize: 14, fontWeight: bold ? FontWeight.w700 : FontWeight.normal)),
        ],
      ),
    );
  }
}
