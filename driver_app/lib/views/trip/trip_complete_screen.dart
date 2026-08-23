import 'package:flutter/material.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';
import 'package:ravelgo_driver_app/views/shell/driver_shell.dart';

/// Shows the real completed Trip's fare (finalFare, set by the driver's own
/// PATCH .../status COMPLETED call and confirmed by the backend). The
/// previous version fabricated a 15% "RavelGo service fee" split — no such
/// fee exists anywhere in the backend's Payment model — and a "Rate your
/// rider" control with no submission endpoint behind it at all; both are
/// gone rather than kept as decoration with nothing real behind them.
class TripCompleteScreen extends StatelessWidget {
  final Map<String, dynamic> trip;
  const TripCompleteScreen({super.key, required this.trip});

  @override
  Widget build(BuildContext context) {
    final fare = (trip['finalFare'] as num?) ?? (trip['estimatedFare'] as num?);

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.check_circle, color: Colors.green, size: 56),
              const SizedBox(height: 12),
              const Text("Trip completed", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: AppComponents.cardDecoration(),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("Trip fare", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                    Text(
                      fare != null ? "₦${fare.toStringAsFixed(0)}" : "—",
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
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
}
