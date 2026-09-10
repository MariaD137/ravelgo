import 'package:flutter/material.dart';
import 'package:ravelgo_driver_app/config/currency.dart';
import 'package:ravelgo_driver_app/services/api_client.dart';
import 'package:ravelgo_driver_app/services/driver_api.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';

/// The driver's own rental listings AND their real bookings — backed
/// entirely by GET /api/rentals/mine (requireRole("Driver"), scoped to the
/// caller's own driver profile server-side, so this can never show another
/// driver's listings). No mock rental records anywhere in this screen.
class MyRentalListingsScreen extends StatefulWidget {
  const MyRentalListingsScreen({super.key});

  @override
  State<MyRentalListingsScreen> createState() => _MyRentalListingsScreenState();
}

class _MyRentalListingsScreenState extends State<MyRentalListingsScreen> {
  bool _loading = true;
  String? _error;
  List<RentalListing> _listings = const [];

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
      final listings = await DriverApi.myRentalListings();
      if (!mounted) return;
      setState(() {
        _listings = listings;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException ? e.message : 'Could not load your rental listings.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Listings')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _errorState()
              : _listings.isEmpty
                  ? _emptyState()
                  : RefreshIndicator(onRefresh: _load, child: _list()),
    );
  }

  Widget _errorState() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.danger)),
            const SizedBox(height: 12),
            TextButton(onPressed: _load, child: const Text('Try again')),
          ]),
        ),
      );

  Widget _emptyState() => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              children: const [
                Icon(Icons.directions_car_outlined, size: 48, color: AppColors.textSecondary),
                SizedBox(height: 12),
                Text(
                  "You haven't listed a car for rental yet.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      );

  Widget _list() {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: _listings.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, i) => _listingCard(_listings[i]),
    );
  }

  Widget _listingCard(RentalListing listing) {
    final vehicle = listing.vehicle;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppComponents.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  vehicle == null ? 'Vehicle' : '${vehicle.brand} ${vehicle.model}'.trim(),
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                ),
              ),
              _statusBadge(listing.status),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${listing.location} · ${Currency.format(listing.dailyRate, decimals: 0)}/day',
            style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
          ),
          if (listing.status == 'PENDING_APPROVAL') ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'Awaiting admin review before customers can book this car.',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ),
          ] else if (listing.status == 'REJECTED') ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.danger.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'This listing was rejected by admin review.',
                style: TextStyle(fontSize: 12, color: AppColors.danger),
              ),
            ),
          ],
          const SizedBox(height: 12),
          const Text('Bookings', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          const SizedBox(height: 6),
          if (listing.bookings.isEmpty)
            const Text('No bookings yet.', style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary))
          else
            ...listing.bookings.map(_bookingRow),
        ],
      ),
    );
  }

  Widget _bookingRow(RentalBooking booking) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(booking.renterName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                Text(
                  '${_formatDate(booking.startDate)} – ${_formatDate(booking.endDate)} (${booking.days}d)',
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(Currency.format(booking.totalPrice, decimals: 0), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 2),
              _statusBadge(booking.status),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Widget _statusBadge(String status) {
    final color = switch (status) {
      'APPROVED' || 'CONFIRMED' || 'COMPLETED' => AppColors.success,
      'REJECTED' || 'CANCELLED' => AppColors.danger,
      _ => AppColors.warning,
    };
    return AppComponents.badge(status.replaceAll('_', ' '), color: color);
  }
}
