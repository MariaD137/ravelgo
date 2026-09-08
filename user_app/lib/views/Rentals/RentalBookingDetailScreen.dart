import 'package:flutter/material.dart';
import 'package:ravelgo_user_app/config/currency.dart';
import 'package:ravelgo_user_app/services/api_client.dart';
import 'package:ravelgo_user_app/services/rental_api.dart';
import 'package:ravelgo_user_app/theme/app_theme.dart';

/// A single rental booking's real status — the screen a RENTAL_BOOKING
/// notification opens (see notification_navigation.dart), and reachable from
/// anywhere a booking id is known. Backed entirely by GET/PATCH
/// /api/rental-bookings/:id (rental_api.dart's `booking`/`cancel`, both
/// already used by the checkout flow — this screen is what was missing to
/// view/manage a booking afterwards). No hardcoded booking data.
class RentalBookingDetailScreen extends StatefulWidget {
  final String bookingId;
  const RentalBookingDetailScreen({super.key, required this.bookingId});

  @override
  State<RentalBookingDetailScreen> createState() => _RentalBookingDetailScreenState();
}

class _RentalBookingDetailScreenState extends State<RentalBookingDetailScreen> {
  bool _loading = true;
  bool _cancelling = false;
  String? _error;
  RentalBooking? _booking;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final booking = await RentalApi.booking(widget.bookingId);
      if (!mounted) return;
      setState(() {
        _booking = booking;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException ? e.message : e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _cancel() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel this booking?'),
        content: const Text('If you already paid, you\'ll be refunded to the same method.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep booking')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Cancel booking')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _cancelling = true);
    try {
      final updated = await RentalApi.cancel(widget.bookingId);
      if (!mounted) return;
      setState(() => _booking = updated);
    } catch (e) {
      if (!mounted) return;
      final message = e is ApiException ? e.message : 'Could not cancel this booking.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _cancelling = false);
    }
  }

  String _fmtDate(String iso) {
    final d = DateTime.tryParse(iso);
    if (d == null) return iso.split('T').first;
    const months = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${d.day} ${months[d.month]} ${d.year}';
  }

  String _prettyStatus(String s) => s.isEmpty ? '' : s[0] + s.substring(1).toLowerCase().replaceAll('_', ' ');

  Color _statusColor(String s) {
    switch (s) {
      case 'CONFIRMED':
      case 'COMPLETED':
        return AppColors.success;
      case 'CANCELLED':
        return AppColors.error;
      default:
        return AppColors.warning;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Rental booking')),
      body: _body(),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null || _booking == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error ?? 'Booking not found', textAlign: TextAlign.center, style: const TextStyle(color: AppColors.error)),
              const SizedBox(height: 8),
              TextButton(onPressed: _load, child: const Text('Try again')),
            ],
          ),
        ),
      );
    }
    final booking = _booking!;
    final vehicle = booking.listing?.vehicle;
    final cancellable = booking.status == 'PENDING_PAYMENT' || booking.status == 'CONFIRMED';

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: AppColors.surfaceElevated, borderRadius: BorderRadius.circular(14)),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    vehicle?.label.isNotEmpty == true ? vehicle!.label : 'Vehicle rental',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: _statusColor(booking.status).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
                  child: Text(_prettyStatus(booking.status), style: TextStyle(color: _statusColor(booking.status), fontWeight: FontWeight.w700, fontSize: 12)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _row('Pick-up', _fmtDate(booking.startDate)),
          _row('Return', _fmtDate(booking.endDate)),
          _row('Duration', '${booking.days} day${booking.days == 1 ? '' : 's'}'),
          if (booking.listing?.location.isNotEmpty == true) _row('Location', booking.listing!.location),
          const Divider(height: 32),
          _row('Payment method', booking.paymentStatus.isEmpty ? 'Not yet paid' : _prettyStatus(booking.paymentStatus)),
          _row('Total', Currency.format(booking.totalPrice, decimals: 0), bold: true),
          if (cancellable) ...[
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _cancelling ? null : _cancel,
                style: OutlinedButton.styleFrom(foregroundColor: AppColors.error, side: const BorderSide(color: AppColors.error)),
                child: _cancelling
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Cancel booking'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _row(String label, String value, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Expanded(child: Text(label, style: const TextStyle(color: AppColors.textSecondary))),
            Text(value, style: TextStyle(fontWeight: bold ? FontWeight.w700 : FontWeight.w600)),
          ],
        ),
      );
}
