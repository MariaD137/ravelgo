import 'package:flutter/material.dart';
import 'package:ravelgo_rider_app/services/api/api_client.dart';
import 'package:ravelgo_rider_app/services/api/rental_api.dart';

/// The rider's real rental bookings — GET /api/rentals/bookings/mine. Each
/// row is a real RentalBooking row in its actual state machine status
/// (REQUESTED/CONFIRMED/ACTIVE/COMPLETED/CANCELLED/REJECTED), not a
/// hardcoded "Booked" label.
class MyRentalBookingsScreen extends StatefulWidget {
  const MyRentalBookingsScreen({super.key, required this.rentalApi});

  final RentalApi rentalApi;

  @override
  State<MyRentalBookingsScreen> createState() => _MyRentalBookingsScreenState();
}

class _MyRentalBookingsScreenState extends State<MyRentalBookingsScreen> {
  late Future<List<Map<String, dynamic>>> _future;
  final Set<String> _cancelling = {};

  @override
  void initState() {
    super.initState();
    _future = widget.rentalApi.myBookings();
  }

  Future<void> _refresh() async {
    final future = widget.rentalApi.myBookings();
    setState(() => _future = future);
    await future;
  }

  Future<void> _cancel(String bookingId) async {
    setState(() => _cancelling.add(bookingId));
    try {
      await widget.rentalApi.cancelBooking(bookingId);
      if (!mounted) return;
      await _refresh();
    } on ApiException catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not cancel: ${err.message}')));
    } finally {
      if (mounted) setState(() => _cancelling.remove(bookingId));
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'COMPLETED':
      case 'ACTIVE':
      case 'CONFIRMED':
        return Colors.green;
      case 'CANCELLED':
      case 'REJECTED':
        return Colors.red;
      default:
        return Colors.orange;
    }
  }

  String _fmt(String? iso) {
    final d = iso == null ? null : DateTime.tryParse(iso)?.toLocal();
    return d == null ? '?' : '${d.day}/${d.month}/${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My bookings'), backgroundColor: Colors.white, foregroundColor: Colors.black, elevation: 0),
      backgroundColor: const Color(0xFFF9F9F9),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  const SizedBox(height: 100),
                  Center(child: Text('Failed to load bookings: ${snapshot.error}', textAlign: TextAlign.center)),
                  const SizedBox(height: 12),
                  Center(child: TextButton(onPressed: _refresh, child: const Text('Retry'))),
                ],
              );
            }
            final bookings = snapshot.data ?? const [];
            if (bookings.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 100),
                  Center(child: Text('No rental bookings yet.', style: TextStyle(color: Colors.black54))),
                ],
              );
            }
            return ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              itemCount: bookings.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final booking = bookings[i];
                final listing = booking['rentalListing'] as Map<String, dynamic>?;
                final vehicle = listing?['vehicle'] as Map<String, dynamic>?;
                final name = vehicle == null ? 'Vehicle unavailable' : '${vehicle['brand']} ${vehicle['model']} (${vehicle['year']})';
                final status = booking['status'] as String? ?? 'REQUESTED';
                final resolvedImageUrl = ApiClient().resolveAssetUrl(vehicle?['imageUrl'] as String?);
                final cancellable = status == 'REQUESTED' || status == 'CONFIRMED';
                final busy = _cancelling.contains(booking['id']);

                return Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade300)),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: SizedBox(
                          width: 64,
                          height: 64,
                          child: resolvedImageUrl != null
                              ? Image.network(
                                  resolvedImageUrl,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) => Container(color: const Color(0xFFECECEC), child: const Icon(Icons.directions_car)),
                                )
                              : Container(color: const Color(0xFFECECEC), child: const Icon(Icons.directions_car)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                            const SizedBox(height: 4),
                            Text('${_fmt(booking['startAt'] as String?)} → ${_fmt(booking['endAt'] as String?)}', style: const TextStyle(fontSize: 12, color: Colors.black54)),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(color: _statusColor(status).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
                                  child: Text(status, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _statusColor(status))),
                                ),
                                const SizedBox(width: 8),
                                Text('₦${((booking['price'] as num?) ?? 0).toStringAsFixed(0)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                              ],
                            ),
                            if (cancellable) ...[
                              const SizedBox(height: 6),
                              TextButton(
                                onPressed: busy ? null : () => _cancel(booking['id'] as String),
                                style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 0), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                                child: Text(busy ? 'Cancelling…' : 'Cancel', style: const TextStyle(color: Colors.red, fontSize: 12)),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
