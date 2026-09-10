import 'package:flutter/material.dart';
import 'package:ravelgo_user_app/config/currency.dart';
import 'package:ravelgo_user_app/services/api_client.dart';
import 'package:ravelgo_user_app/services/rental_api.dart';
import 'package:ravelgo_user_app/services/paystack_service.dart';
import 'package:ravelgo_user_app/theme/app_theme.dart';
import 'package:ravelgo_user_app/views/Rentals/RentalConfirmationScreen.dart';

/// Pay for an already-created (PENDING_PAYMENT) rental booking. Mirrors the
/// ride payment flow: CARD opens a backend-issued Paystack checkout page,
/// WALLET settles immediately from the customer's RavelGo Cash balance. The
/// amount is always the server-side booking.totalPrice.
class RentalCheckoutScreen extends StatefulWidget {
  final RentalBooking booking;
  final RentalListing listing;
  const RentalCheckoutScreen({super.key, required this.booking, required this.listing});

  @override
  State<RentalCheckoutScreen> createState() => _RentalCheckoutScreenState();
}

class _RentalCheckoutScreenState extends State<RentalCheckoutScreen> {
  bool _isCardSelected = true;
  bool _paying = false;

  Future<void> _pay() async {
    if (_paying) return;
    setState(() => _paying = true);
    try {
      RentalBooking confirmed;
      if (_isCardSelected) {
        final authorizationUrl = await RentalApi.payWithCard(widget.booking.id);
        await PaystackService.openCheckout(authorizationUrl);
        // Opening the checkout page doesn't itself flip the booking to
        // CONFIRMED — that happens on the signed Paystack webhook once the
        // customer completes payment in the browser, which this app has no
        // way to observe directly. Re-fetch so the confirmation screen
        // reflects the real, current backend state either way.
        confirmed = await RentalApi.booking(widget.booking.id);
      } else {
        confirmed = await RentalApi.payWithWallet(widget.booking.id);
      }
      if (!mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => RentalConfirmationScreen(booking: confirmed, listing: widget.listing)));
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final booking = widget.booking;
    final listing = widget.listing;
    return Scaffold(
      appBar: AppBar(title: const Text('Review & pay')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: AppColors.surfaceElevated, borderRadius: BorderRadius.circular(14)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(listing.vehicle?.label.isNotEmpty == true ? listing.vehicle!.label : 'Vehicle',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  const SizedBox(height: 4),
                  Text(listing.location, style: const TextStyle(color: AppColors.textMuted)),
                  const SizedBox(height: 12),
                  _row('Pick-up', booking.startDate.split('T').first),
                  _row('Return', booking.endDate.split('T').first),
                  _row('Days', '${booking.days}'),
                  const Divider(height: 24),
                  _row('Total', Currency.format(booking.totalPrice, decimals: 0), bold: true),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const Text('Pay with', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 8),
            for (final m in const ['Card', 'RavelGo Cash'])
              RadioListTile<bool>(
                title: Text(m),
                value: m == 'Card',
                groupValue: _isCardSelected,
                onChanged: (v) => setState(() => _isCardSelected = v!),
              ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _paying ? null : _pay,
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, padding: const EdgeInsets.symmetric(vertical: 14)),
                child: _paying
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text('Pay ${Currency.format(booking.totalPrice, decimals: 0)}', style: const TextStyle(color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(color: AppColors.textSecondary)),
            Text(value, style: TextStyle(fontWeight: bold ? FontWeight.w700 : FontWeight.w500)),
          ],
        ),
      );
}
