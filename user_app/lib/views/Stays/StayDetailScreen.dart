import 'package:flutter/material.dart';
import 'package:ravelgo_user_app/config/currency.dart';
import 'package:ravelgo_user_app/services/api_client.dart';
import 'package:ravelgo_user_app/services/stays_api.dart';
import 'package:ravelgo_user_app/theme/app_theme.dart';

class StayDetailScreen extends StatefulWidget {
  final String listingId;
  const StayDetailScreen({super.key, required this.listingId});

  @override
  State<StayDetailScreen> createState() => _StayDetailScreenState();
}

class _StayDetailScreenState extends State<StayDetailScreen> {
  bool _loading = true;
  String? _error;
  PropertyListing? _listing;

  DateTime? _checkIn;
  DateTime? _checkOut;
  int _guests = 1;
  bool _booking = false;

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
      final listing = await StaysApi.listing(widget.listingId);
      if (!mounted) return;
      setState(() {
        _listing = listing;
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

  Future<void> _pickCheckIn() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _checkIn ?? now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked == null) return;
    setState(() {
      _checkIn = picked;
      // Keep checkout valid (after the new check-in) instead of leaving a
      // stale date that would fail server-side validation.
      if (_checkOut == null || !_checkOut!.isAfter(_checkIn!)) {
        _checkOut = _checkIn!.add(const Duration(days: 1));
      }
    });
  }

  Future<void> _pickCheckOut() async {
    if (_checkIn == null) return;
    final picked = await showDatePicker(
      context: context,
      initialDate: _checkOut ?? _checkIn!.add(const Duration(days: 1)),
      firstDate: _checkIn!.add(const Duration(days: 1)),
      lastDate: _checkIn!.add(const Duration(days: 365)),
    );
    if (picked == null) return;
    setState(() => _checkOut = picked);
  }

  int get _nights =>
      _checkIn != null && _checkOut != null ? _checkOut!.difference(_checkIn!).inDays : 0;

  Future<void> _book() async {
    final listing = _listing;
    if (listing == null || _checkIn == null || _checkOut == null) return;
    setState(() => _booking = true);
    try {
      final booking = await StaysApi.book(
        propertyId: listing.id,
        checkIn: _checkIn!,
        checkOut: _checkOut!,
        guests: _guests,
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Booking confirmed'),
          content: Text(
            '${booking.nights} night${booking.nights == 1 ? '' : 's'} at ${listing.title}\n'
            'Total: ${Currency.format(booking.totalPrice, decimals: 0)}',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
          ],
        ),
      );
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      final message = e is ApiException ? e.message : 'Could not complete this booking.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _booking = false);
    }
  }

  String _fmtDate(DateTime? d) {
    if (d == null) return 'Select date';
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_listing?.title ?? 'Stay')),
      body: _body(),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null || _listing == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error ?? 'Listing not found', textAlign: TextAlign.center, style: const TextStyle(color: AppColors.error)),
              TextButton(onPressed: _load, child: const Text('Try again')),
            ],
          ),
        ),
      );
    }
    final listing = _listing!;
    final canBook = _checkIn != null && _checkOut != null && _nights > 0 && !_booking;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: listing.imageUrl != null && listing.imageUrl!.isNotEmpty
                ? Image.network(listing.imageUrl!, width: double.infinity, height: 180, fit: BoxFit.cover)
                : Container(
                    width: double.infinity,
                    height: 180,
                    color: AppColors.surfaceElevated,
                    child: const Icon(Icons.apartment_outlined, size: 48, color: AppColors.primaryDark),
                  ),
          ),
          const SizedBox(height: 16),
          Text(listing.title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(listing.address, style: const TextStyle(color: AppColors.textMuted)),
          const SizedBox(height: 8),
          Text(
            '${Currency.format(listing.pricePerNight, decimals: 0)} / night · up to ${listing.maxGuests} guests',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          if (listing.description != null && listing.description!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(listing.description!, style: const TextStyle(color: AppColors.textSecondary)),
          ],
          const SizedBox(height: 24),
          const Text('Request to book', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _pickCheckIn,
                  child: Text('Check-in: ${_fmtDate(_checkIn)}'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: _checkIn == null ? null : _pickCheckOut,
                  child: Text('Check-out: ${_fmtDate(_checkOut)}'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Text('Guests', style: TextStyle(fontWeight: FontWeight.w600)),
              const Spacer(),
              IconButton(
                onPressed: _guests > 1 ? () => setState(() => _guests--) : null,
                icon: const Icon(Icons.remove_circle_outline),
              ),
              Text('$_guests', style: const TextStyle(fontWeight: FontWeight.w700)),
              IconButton(
                onPressed: _guests < listing.maxGuests ? () => setState(() => _guests++) : null,
                icon: const Icon(Icons.add_circle_outline),
              ),
            ],
          ),
          if (_nights > 0) ...[
            const SizedBox(height: 8),
            Text(
              '$_nights night${_nights == 1 ? '' : 's'} · total ${Currency.format(listing.pricePerNight * _nights, decimals: 0)}',
              style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.primaryDark),
            ),
          ],
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: canBook ? _book : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: _booking
                  ? const SizedBox(
                      width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Request to book'),
            ),
          ),
        ],
      ),
    );
  }
}
