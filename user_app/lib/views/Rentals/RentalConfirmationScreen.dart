import 'package:flutter/material.dart';
import 'package:ravelgo_user_app/config/currency.dart';
import 'package:ravelgo_user_app/services/rental_api.dart';
import 'package:ravelgo_user_app/theme/app_theme.dart';

/// Shown after a real booking is created/paid. Reflects the actual backend
/// state — a CARD payment may still show PENDING_PAYMENT here if Paystack's
/// webhook hasn't landed yet; nothing on this screen is fabricated.
class RentalConfirmationScreen extends StatelessWidget {
  final RentalBooking booking;
  final RentalListing listing;
  const RentalConfirmationScreen({super.key, required this.booking, required this.listing});

  bool get _confirmed => booking.status == 'CONFIRMED';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(automaticallyImplyLeading: false, title: const Text('Booking')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(_confirmed ? Icons.check_circle : Icons.hourglass_top, size: 64, color: _confirmed ? AppColors.success : AppColors.warning),
            const SizedBox(height: 16),
            Text(
              _confirmed ? 'Booking confirmed' : 'Payment processing',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              _confirmed
                  ? 'Your rental is booked. You\'ll find it under My Activity.'
                  : 'We\'re confirming your payment with the bank — this booking will update automatically once it\'s done.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 24),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: AppColors.surfaceElevated, borderRadius: BorderRadius.circular(14)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(listing.vehicle?.label.isNotEmpty == true ? listing.vehicle!.label : 'Vehicle',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text('${booking.startDate.split('T').first} → ${booking.endDate.split('T').first}',
                      style: const TextStyle(color: AppColors.textSecondary)),
                  const SizedBox(height: 4),
                  Text('Booking #${booking.id.substring(0, 8)} · ${Currency.format(booking.totalPrice, decimals: 0)}',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, padding: const EdgeInsets.symmetric(vertical: 14)),
                child: const Text('Done', style: TextStyle(color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
