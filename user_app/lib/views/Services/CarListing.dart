import 'package:flutter/material.dart';
import 'package:ravelgo_rider_app/services/api/api_client.dart';
import 'package:ravelgo_rider_app/services/api/rental_api.dart';

import 'BookRentalScreen.dart';
import 'MyRentalBookingsScreen.dart';

/// Real, approved rental listings — GET /api/rentals, backed by actual
/// Vehicle/RentalListing rows (not a hardcoded sample inventory). Each card
/// shows the listing's real photo (or a clean "no photo" placeholder),
/// make/model/year/colour, daily rate, and location; tapping one opens
/// [BookRentalScreen] to request a real RentalBooking through the existing
/// rental API. "My bookings" (app bar) surfaces the rider's own existing
/// bookings via GET /api/rentals/bookings/mine.
class CarListing extends StatefulWidget {
  CarListing({super.key, RentalApi? rentalApi}) : rentalApi = rentalApi ?? RentalApi(ApiClient());

  final RentalApi rentalApi;

  @override
  State<CarListing> createState() => _CarListingState();
}

class _CarListingState extends State<CarListing> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.rentalApi.browseListings();
  }

  Future<void> _refresh() async {
    final future = widget.rentalApi.browseListings();
    setState(() => _future = future);
    await future;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9F9F9),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text('Rent a car', style: TextStyle(color: Colors.black)),
        iconTheme: const IconThemeData(color: Colors.black),
        actions: [
          IconButton(
            icon: const Icon(Icons.event_note_outlined),
            tooltip: 'My bookings',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MyRentalBookingsScreen(rentalApi: widget.rentalApi))),
          ),
        ],
      ),
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
                  Center(child: Text('Failed to load listings: ${snapshot.error}', textAlign: TextAlign.center)),
                  const SizedBox(height: 12),
                  Center(child: TextButton(onPressed: _refresh, child: const Text('Retry'))),
                ],
              );
            }
            final listings = snapshot.data ?? const [];
            if (listings.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 100),
                  Center(child: Text('No cars available for rent right now.', style: TextStyle(color: Colors.black54))),
                ],
              );
            }
            return GridView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              itemCount: listings.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.72,
              ),
              itemBuilder: (context, i) => _ListingCard(
                listing: listings[i],
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => BookRentalScreen(listing: listings[i], rentalApi: widget.rentalApi)),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ListingCard extends StatelessWidget {
  const _ListingCard({required this.listing, required this.onTap});

  final Map<String, dynamic> listing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final vehicle = listing['vehicle'] as Map<String, dynamic>?;
    final name = vehicle == null ? 'Vehicle unavailable' : '${vehicle['brand']} ${vehicle['model']}';
    final details = vehicle == null ? '' : '${vehicle['year']} · ${vehicle['colour']}';
    final resolvedImageUrl = ApiClient().resolveAssetUrl(vehicle?['imageUrl'] as String?);
    final dailyRate = (listing['dailyRate'] as num?)?.toDouble() ?? 0;
    final location = listing['location'] as String? ?? '';

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(border: Border.all(color: Colors.green, width: 1), borderRadius: BorderRadius.circular(12)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
                child: AspectRatio(
                  aspectRatio: 16 / 10,
                  child: resolvedImageUrl != null
                      ? Image.network(resolvedImageUrl, fit: BoxFit.cover, errorBuilder: (_, _, _) => const _NoCarPhoto())
                      : const _NoCarPhoto(),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: const TextStyle(fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                    if (details.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(details, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                    ],
                    const SizedBox(height: 6),
                    Text('₦${dailyRate.toStringAsFixed(0)} / day', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                    if (location.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(location, style: const TextStyle(color: Colors.grey, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A clean, honest placeholder — never a stand-in image that could be
/// mistaken for the actual vehicle.
class _NoCarPhoto extends StatelessWidget {
  const _NoCarPhoto();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFECECEC),
      alignment: Alignment.center,
      child: const Icon(Icons.directions_car, color: Colors.black26, size: 28),
    );
  }
}
