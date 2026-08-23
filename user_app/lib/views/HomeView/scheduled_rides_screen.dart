import 'package:flutter/material.dart';

/// Scheduled ("book ahead") rides have no backend representation yet — Trip
/// has no scheduled-time field, and there is no ride-offer/broadcast model
/// multiple drivers could accept from (POST /trips matches exactly one
/// driver synchronously; see services/matching.ts). The previous version of
/// this screen showed fixed placeholder requests ("Tomorrow, 30 Mar,
/// 14:30", a flat "NGN 8,000" fare) whose Accept button didn't call the
/// backend at all. Building real ride scheduling means a new Trip field, a
/// scheduling job/worker, and a driver-facing broadcast/accept flow — out
/// of scope here. This screen shows that honestly instead.
class ScheduledRidesRequestsScreen extends StatelessWidget {
  const ScheduledRidesRequestsScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back)),
                  const Expanded(
                    child: Center(
                      child: Text("Scheduled Rides", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.schedule_outlined, size: 48, color: Colors.black38),
                        const SizedBox(height: 16),
                        const Text(
                          "Scheduled rides aren't available yet",
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          "Booking a ride ahead of time is a planned feature — for now, request a ride from "
                          "the home screen when you're ready to go.",
                          style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
