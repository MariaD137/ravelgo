import 'package:flutter/material.dart';
import 'package:ravelgo_driver_app/config/currency.dart';
import 'package:ravelgo_driver_app/services/driver_api.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';
import 'package:ravelgo_driver_app/views/shell/driver_shell.dart';
import 'package:ravelgo_driver_app/widgets/app_page_route.dart';

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
    // The backend has finalized the trip; use its real fare and, when the
    // trip's payment has already settled, its real locked-in commission
    // split (commissionRate/platformCommission/driverEarnings — see
    // backend/src/services/ledger.ts). Payment settlement can happen after
    // trip completion, so those fields may still be null at this exact
    // moment; the 20% fallback here matches the platform's real default
    // (DEFAULT_COMMISSION_RATE in backend/src/services/commission.ts), the
    // same fallback IncomingRequestSheet already uses, rather than an
    // arbitrary, wrong 25%.
    final fare = widget.trip.fare;
    final commissionRate = widget.trip.commissionRate ?? 0.2;
    final platformFee = widget.trip.platformCommission ?? (fare * commissionRate);
    final earnings = widget.trip.driverEarnings ?? (fare - platformFee);

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
                    AppPageRoute(builder: (_) => const DriverShell()),
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
