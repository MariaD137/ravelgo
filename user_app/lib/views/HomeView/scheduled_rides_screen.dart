import 'package:flutter/material.dart';
import 'package:ravelgo_user_app/theme/app_theme.dart';

/// Scheduling a ride in advance isn't built yet — the backend's Trip model
/// has no concept of a future-dated booking (unlike RentalBooking, which
/// genuinely does support date ranges). This screen used to always show two
/// fabricated pending "requests" and three fabricated "confirmed" rides
/// (fake pickup/destination labels, a made-up ₦8,000 fare, and working
/// Accept/Decline buttons — Accept even flipped the app's real
/// ride-in-progress state for a ride that was never requested). The
/// `hasRequests`/`hasConfirm` flags that were meant to gate an empty state
/// both defaulted to false, so the fake cards were the ONLY thing this
/// screen ever showed. Replaced with an honest "not available yet" state.
class ScheduledRidesRequestsScreen extends StatelessWidget {
  const ScheduledRidesRequestsScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back),
                  ),
                  const Expanded(
                    child: Center(
                      child: Text(
                        "Scheduled rides",
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  const SizedBox(width: 48), // balance arrow space
                ],
              ),
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.event_outlined, size: 48, color: AppColors.textMuted),
                        const SizedBox(height: 16),
                        const Text(
                          "Scheduled rides aren't available yet",
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          "You can't book a ride ahead of time yet — request one for right now from the home screen.",
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
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
