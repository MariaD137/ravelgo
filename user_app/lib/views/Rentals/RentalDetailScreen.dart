import 'package:flutter/material.dart';
import 'package:ravelgo_user_app/config/currency.dart';
import 'package:ravelgo_user_app/services/api_client.dart';
import 'package:ravelgo_user_app/services/rental_api.dart';
import 'package:ravelgo_user_app/theme/app_theme.dart';
import 'package:ravelgo_user_app/views/Rentals/RentalCheckoutScreen.dart';

class RentalDetailScreen extends StatefulWidget {
  final String listingId;
  const RentalDetailScreen({super.key, required this.listingId});

  @override
  State<RentalDetailScreen> createState() => _RentalDetailScreenState();
}

class _RentalDetailScreenState extends State<RentalDetailScreen> {
  bool _loading = true;
  String? _error;
  RentalListing? _listing;

  DateTime? _startDate;
  DateTime? _endDate;
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
      final listing = await RentalApi.listing(widget.listingId);
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

  Future<void> _pickStartDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate ?? now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked == null) return;
    setState(() {
      _startDate = picked;
      if (_endDate == null || !_endDate!.isAfter(_startDate!)) {
        _endDate = _startDate!.add(const Duration(days: 1));
      }
    });
  }

  Future<void> _pickEndDate() async {
    if (_startDate == null) return;
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate ?? _startDate!.add(const Duration(days: 1)),
      firstDate: _startDate!.add(const Duration(days: 1)),
      lastDate: _startDate!.add(const Duration(days: 365)),
    );
    if (picked == null) return;
    setState(() => _endDate = picked);
  }

  int get _days => _startDate != null && _endDate != null ? _endDate!.difference(_startDate!).inDays : 0;

  Future<void> _continue() async {
    final listing = _listing;
    if (listing == null || _startDate == null || _endDate == null) return;
    setState(() => _booking = true);
    try {
      final booking = await RentalApi.book(listingId: listing.id, startDate: _startDate!, endDate: _endDate!);
      if (!mounted) return;
      await Navigator.push(context, MaterialPageRoute(builder: (_) => RentalCheckoutScreen(booking: booking, listing: listing)));
    } catch (e) {
      if (!mounted) return;
      final message = e is ApiException ? e.message : 'Could not reserve this vehicle.';
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
      appBar: AppBar(title: Text(_listing?.vehicle?.label.isNotEmpty == true ? _listing!.vehicle!.label : 'Vehicle')),
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
              Text(_error ?? 'Vehicle not found', textAlign: TextAlign.center, style: const TextStyle(color: AppColors.error)),
              TextButton(onPressed: _load, child: const Text('Try again')),
            ],
          ),
        ),
      );
    }
    final listing = _listing!;
    final vehicle = listing.vehicle;
    final canContinue = _startDate != null && _endDate != null && _days > 0 && !_booking;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            height: 160,
            decoration: BoxDecoration(color: AppColors.surfaceElevated, borderRadius: BorderRadius.circular(14)),
            child: const Icon(Icons.directions_car, size: 64, color: AppColors.primaryDark),
          ),
          const SizedBox(height: 16),
          Text(vehicle?.label.isNotEmpty == true ? vehicle!.label : 'Vehicle', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(listing.location, style: const TextStyle(color: AppColors.textMuted)),
          if (vehicle != null) ...[
            const SizedBox(height: 8),
            Text('${vehicle.colour} · ${vehicle.year}', style: const TextStyle(color: AppColors.textSecondary)),
          ],
          const SizedBox(height: 8),
          Text('${Currency.format(listing.dailyRate, decimals: 0)} / day', style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 24),
          const Text('Choose your dates', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: OutlinedButton(onPressed: _pickStartDate, child: Text('Pick-up: ${_fmtDate(_startDate)}'))),
              const SizedBox(width: 8),
              Expanded(child: OutlinedButton(onPressed: _startDate == null ? null : _pickEndDate, child: Text('Return: ${_fmtDate(_endDate)}'))),
            ],
          ),
          if (_days > 0) ...[
            const SizedBox(height: 12),
            Text(
              '$_days day${_days == 1 ? '' : 's'} · total ${Currency.format(listing.dailyRate * _days, decimals: 0)}',
              style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.primaryDark),
            ),
          ],
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: canContinue ? _continue : null,
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, padding: const EdgeInsets.symmetric(vertical: 14)),
              child: _booking
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Continue', style: TextStyle(color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }
}
