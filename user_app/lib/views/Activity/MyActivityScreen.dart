import 'package:flutter/material.dart';
import 'package:ravelgo_user_app/config/currency.dart';
import 'package:ravelgo_user_app/services/api_client.dart';
import 'package:ravelgo_user_app/services/courier_api.dart';
import 'package:ravelgo_user_app/services/rental_api.dart';
import 'package:ravelgo_user_app/services/stays_api.dart';
import 'package:ravelgo_user_app/services/trips_api.dart';
import 'package:ravelgo_user_app/theme/app_theme.dart';
import 'package:ravelgo_user_app/views/Rentals/RentalBookingDetailScreen.dart';

/// Mirrors courierMayCancel() in backend/src/routes/courier.routes.ts — a
/// delivery is only cancellable before a driver has physically picked the
/// package up.
bool _isCancellableDeliveryStatus(String status) =>
    status == 'REQUESTED' || status == 'MATCHED';

/// A single row across every service — the actual persisted backend record,
/// not a fabricated one. Rides, rentals and deliveries each come from their
/// own real endpoint; there is no unified backend model, so this normalizes
/// them client-side purely for display.
class _ActivityEntry {
  final String type; // Ride | Car Rental | Delivery | Short Stay
  final IconData icon;
  final String title;
  final String subtitle;
  final String status;
  final Color statusColor;
  final DateTime date;
  final double amount;
  final Map<String, String> details;
  // Only set for rentals, which have a real dedicated detail screen
  // (RentalBookingDetailScreen) — rides/deliveries still use the inline
  // details sheet below.
  final String? rentalBookingId;
  // Only set for deliveries — the CourierRequest's own id, needed to call
  // CourierApi.cancel(). Rides already have a working cancel path on
  // SearchDriverScreen (while actively searching/matched); this screen does
  // not duplicate that one.
  final String? courierRequestId;

  _ActivityEntry({
    required this.type,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.status,
    required this.statusColor,
    required this.date,
    required this.amount,
    required this.details,
    this.rentalBookingId,
    this.courierRequestId,
  });
}

/// Everything this customer has done across all five services, in one place.
/// Each list comes from its own real backend query.
class MyActivityScreen extends StatefulWidget {
  const MyActivityScreen({super.key});

  @override
  State<MyActivityScreen> createState() => _MyActivityScreenState();
}

class _MyActivityScreenState extends State<MyActivityScreen> {
  bool _loading = true;
  String? _error;
  List<_ActivityEntry> _entries = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Color _rideColor(String s) {
    switch (s) {
      case 'COMPLETED':
        return AppColors.success;
      case 'CANCELLED':
      case 'DISPUTED':
        return AppColors.error;
      default:
        return AppColors.primaryDark;
    }
  }

  Color _rentalColor(String s) {
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

  Color _stayColor(String s) {
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

  Color _deliveryColor(String s) {
    switch (s) {
      case 'DELIVERED':
        return AppColors.success;
      case 'CANCELLED':
        return AppColors.error;
      case 'IN_TRANSIT':
      case 'MATCHED':
        return AppColors.primaryDark;
      default:
        return AppColors.warning;
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait<dynamic>([
        TripsApi.mine().catchError((_) => <Trip>[]),
        RentalApi.myBookings().catchError((_) => <RentalBooking>[]),
        CourierApi.sent().catchError((_) => <CourierRequest>[]),
        StaysApi.myBookings().catchError((_) => <StayBooking>[]),
      ]);
      final trips = results[0] as List<Trip>;
      final rentals = results[1] as List<RentalBooking>;
      final deliveries = results[2] as List<CourierRequest>;
      final stays = results[3] as List<StayBooking>;

      final entries = <_ActivityEntry>[
        ...trips.map(
          (t) => _ActivityEntry(
            type: 'Ride',
            icon: Icons.directions_car_filled,
            title: '${t.pickup} → ${t.destination}',
            subtitle: t.driverName ?? 'Ride',
            status: t.status,
            statusColor: _rideColor(t.status),
            date: t.requestedAt,
            amount: t.fare,
            details: {
              'Pickup': t.pickup,
              'Destination': t.destination,
              'Status': t.status,
              'Driver': t.driverName ?? '—',
              'Fare': Currency.format(t.fare, decimals: 0),
              'Requested': t.requestedAt.toString().split('.').first,
            },
          ),
        ),
        ...rentals.map(
          (r) => _ActivityEntry(
            type: 'Car Rental',
            icon: Icons.directions_car,
            title: r.listing?.vehicle?.label.isNotEmpty == true
                ? r.listing!.vehicle!.label
                : 'Vehicle rental',
            subtitle:
                '${r.startDate.split('T').first} → ${r.endDate.split('T').first}',
            status: r.status,
            statusColor: _rentalColor(r.status),
            date: DateTime.tryParse(r.startDate) ?? DateTime.now(),
            amount: r.totalPrice,
            details: {
              'Vehicle': r.listing?.vehicle?.label ?? '—',
              'Pick-up': r.startDate.split('T').first,
              'Return': r.endDate.split('T').first,
              'Days': '${r.days}',
              'Status': r.status,
              'Payment': r.paymentStatus,
              'Total': Currency.format(r.totalPrice, decimals: 0),
            },
            rentalBookingId: r.id,
          ),
        ),
        ...deliveries.map(
          (d) => _ActivityEntry(
            type: 'Delivery',
            icon: Icons.local_shipping_outlined,
            title: '${d.pickupAddress} → ${d.dropoffAddress}',
            subtitle: d.packageDescription.isEmpty
                ? d.packageSize
                : d.packageDescription,
            status: d.status,
            statusColor: _deliveryColor(d.status),
            date: d.requestedAt,
            amount: d.finalFare ?? d.estimatedFare,
            details: {
              'Pickup': d.pickupAddress,
              'Drop-off': d.dropoffAddress,
              'Recipient': '${d.recipientName} · ${d.recipientPhone}',
              'Status': d.status,
              'Price': Currency.format(
                d.finalFare ?? d.estimatedFare,
                decimals: 0,
              ),
              'Requested': d.requestedAt.toString().split('.').first,
            },
            courierRequestId: d.id,
          ),
        ),
        ...stays.map(
          (s) => _ActivityEntry(
            type: 'Short Stay',
            icon: Icons.hotel_outlined,
            title: s.property?.title.isNotEmpty == true ? s.property!.title : 'Stay booking',
            subtitle: '${s.checkIn.split('T').first} → ${s.checkOut.split('T').first}',
            status: s.status,
            statusColor: _stayColor(s.status),
            date: DateTime.tryParse(s.checkIn) ?? DateTime.now(),
            amount: s.totalPrice,
            details: {
              'Property': s.property?.title ?? '—',
              'Check-in': s.checkIn.split('T').first,
              'Check-out': s.checkOut.split('T').first,
              'Nights': '${s.nights}',
              'Guests': '${s.guests}',
              'Status': s.status,
              'Total': Currency.format(s.totalPrice, decimals: 0),
            },
          ),
        ),
      ]..sort((a, b) => b.date.compareTo(a.date));

      if (!mounted) return;
      setState(() {
        _entries = entries;
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

  void _showDetails(_ActivityEntry entry) {
    final canCancel =
        entry.courierRequestId != null &&
        _isCancellableDeliveryStatus(entry.status);
    bool cancelling = false;
    String? cancelError;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setState) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(entry.icon, color: AppColors.primaryDark),
                  const SizedBox(width: 8),
                  Text(
                    entry.type,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              for (final e in entry.details.entries)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 100,
                        child: Text(
                          e.key,
                          style: const TextStyle(color: AppColors.textMuted),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          e.value,
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                ),
              if (cancelError != null) ...[
                const SizedBox(height: 8),
                Text(
                  cancelError!,
                  style: const TextStyle(color: AppColors.error, fontSize: 13),
                ),
              ],
              if (canCancel) ...[
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.error,
                    ),
                    onPressed: cancelling
                        ? null
                        : () async {
                            setState(() {
                              cancelling = true;
                              cancelError = null;
                            });
                            try {
                              await CourierApi.cancel(entry.courierRequestId!);
                              if (sheetContext.mounted) {
                                Navigator.pop(sheetContext);
                              }
                              _load();
                            } catch (e) {
                              setState(() {
                                cancelling = false;
                                cancelError = e is ApiException
                                    ? e.message
                                    : e.toString();
                              });
                            }
                          },
                    child: Text(cancelling ? 'Cancelling…' : 'Cancel delivery'),
                  ),
                ),
              ],
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Activity')),
      body: _body(),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.error),
              ),
              TextButton(onPressed: _load, child: const Text('Try again')),
            ],
          ),
        ),
      );
    }
    if (_entries.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No activity yet. Book a ride, rent a car, send a package, or book a stay to see it here.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _entries.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          final e = _entries[i];
          return InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => e.rentalBookingId != null
                ? Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => RentalBookingDetailScreen(
                        bookingId: e.rentalBookingId!,
                      ),
                    ),
                  )
                : _showDetails(e),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: AppColors.surfaceElevated,
                    child: Icon(e.icon, color: AppColors.primaryDark, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              e.type,
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.textMuted,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          e.title,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${e.date}'.split(' ').first,
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        Currency.format(e.amount, decimals: 0),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        e.status,
                        style: TextStyle(
                          color: e.statusColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
