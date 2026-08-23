import 'package:flutter/material.dart';
import 'package:ravelgo_rider_app/services/api/api_client.dart';
import 'package:ravelgo_rider_app/services/api/rental_api.dart';

/// Requests a real RentalBooking for one listing — POST
/// /api/rentals/:id/bookings. The booking is created in REQUESTED status
/// (the real state machine — see services/rentals.ts on the backend); this
/// screen never claims the car is "booked" before the backend actually
/// says so, and surfaces a real RENTAL_OVERLAP conflict if the chosen dates
/// clash with another confirmed/active booking on the same vehicle.
class BookRentalScreen extends StatefulWidget {
  const BookRentalScreen({super.key, required this.listing, required this.rentalApi});

  final Map<String, dynamic> listing;
  final RentalApi rentalApi;

  @override
  State<BookRentalScreen> createState() => _BookRentalScreenState();
}

class _BookRentalScreenState extends State<BookRentalScreen> {
  DateTime? _startAt;
  DateTime? _endAt;
  bool _submitting = false;
  String? _error;

  double get _dailyRate => (widget.listing['dailyRate'] as num?)?.toDouble() ?? 0;

  int get _nights {
    if (_startAt == null || _endAt == null) return 0;
    final diff = _endAt!.difference(_startAt!).inMilliseconds;
    return diff <= 0 ? 0 : (diff / (24 * 60 * 60 * 1000)).ceil();
  }

  Future<void> _pickStart() async {
    final now = DateTime.now();
    final picked = await showDatePicker(context: context, initialDate: now, firstDate: now, lastDate: now.add(const Duration(days: 365)));
    if (picked == null) return;
    setState(() {
      _startAt = picked;
      if (_endAt != null && !_endAt!.isAfter(_startAt!)) _endAt = null;
    });
  }

  Future<void> _pickEnd() async {
    final start = _startAt;
    if (start == null) return;
    final earliestEnd = start.add(const Duration(days: 1));
    final picked = await showDatePicker(context: context, initialDate: earliestEnd, firstDate: earliestEnd, lastDate: start.add(const Duration(days: 365)));
    if (picked == null) return;
    setState(() => _endAt = picked);
  }

  Future<void> _confirm() async {
    final start = _startAt;
    final end = _endAt;
    if (start == null || end == null) {
      setState(() => _error = 'Choose a start and end date.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final booking = await widget.rentalApi.createBooking(
        rentalListingId: widget.listing['id'] as String,
        startAt: start,
        endAt: end,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Booking requested (${booking['status']}). We\'ll confirm it shortly.')),
      );
      Navigator.pop(context);
    } on ApiException catch (err) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = err.code == 'RENTAL_OVERLAP' ? 'Those dates are no longer available for this car — try a different range.' : err.message;
      });
    }
  }

  String _fmt(DateTime? d) => d == null ? 'Select date' : '${d.day}/${d.month}/${d.year}';

  @override
  Widget build(BuildContext context) {
    final vehicle = widget.listing['vehicle'] as Map<String, dynamic>?;
    final name = vehicle == null ? 'Vehicle unavailable' : '${vehicle['brand']} ${vehicle['model']} (${vehicle['year']})';
    final resolvedImageUrl = ApiClient().resolveAssetUrl(vehicle?['imageUrl'] as String?);
    final estimatedTotal = _dailyRate * _nights;

    return Scaffold(
      appBar: AppBar(title: const Text('Book this car'), backgroundColor: Colors.white, foregroundColor: Colors.black, elevation: 0),
      backgroundColor: const Color(0xFFF9F9F9),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: resolvedImageUrl != null
                  ? Image.network(
                      resolvedImageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(color: const Color(0xFFECECEC), child: const Icon(Icons.directions_car, size: 32)),
                    )
                  : Container(color: const Color(0xFFECECEC), child: const Icon(Icons.directions_car, size: 32)),
            ),
          ),
          const SizedBox(height: 12),
          Text(name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('₦${_dailyRate.toStringAsFixed(0)} / day · ${widget.listing['location'] ?? ''}', style: const TextStyle(color: Colors.black54)),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _pickStart,
                  child: Text('From: ${_fmt(_startAt)}'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: _startAt == null ? null : _pickEnd,
                  child: Text('To: ${_fmt(_endAt)}'),
                ),
              ),
            ],
          ),
          if (_nights > 0) ...[
            const SizedBox(height: 16),
            Text('$_nights night${_nights == 1 ? '' : 's'} · Estimated total: ₦${estimatedTotal.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
          ],
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.yellow, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              onPressed: _submitting ? null : _confirm,
              child: Text(_submitting ? 'Requesting…' : 'Request booking', style: const TextStyle(color: Colors.black)),
            ),
          ),
        ],
      ),
    );
  }
}
