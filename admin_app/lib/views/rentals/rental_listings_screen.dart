import 'package:flutter/material.dart';
import 'package:ravelgo_admin/models/rental_listing.dart';
import 'package:ravelgo_admin/services/api/api_client.dart';
import 'package:ravelgo_admin/services/api/rental_api.dart';
import 'package:ravelgo_admin/theme/app_theme.dart';

class RentalListingsScreen extends StatefulWidget {
  final RentalApi? rentalApi;
  const RentalListingsScreen({super.key, this.rentalApi});

  @override
  State<RentalListingsScreen> createState() => _RentalListingsScreenState();
}

class _RentalListingsScreenState extends State<RentalListingsScreen> {
  late final RentalApi _api = widget.rentalApi ?? RentalApi(ApiClient());
  late Future<List<RentalListing>> _future;
  final Set<String> _mutatingIds = {};

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<RentalListing>> _load() async {
    final raw = await _api.listListings();
    return raw.map(RentalListing.fromJson).toList();
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  Future<void> _decide(RentalListing listing, String status) async {
    setState(() => _mutatingIds.add(listing.id));
    try {
      await _api.decideListing(listing.id, status);
      if (!mounted) return;
      await _refresh();
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to update listing: $err')));
    } finally {
      if (mounted) setState(() => _mutatingIds.remove(listing.id));
    }
  }

  Color _statusColor(RentalListingStatus s) {
    switch (s) {
      case RentalListingStatus.pendingApproval:
        return AppColors.warning;
      case RentalListingStatus.approved:
        return AppColors.success;
      case RentalListingStatus.rejected:
        return AppColors.danger;
    }
  }

  String _statusLabel(RentalListingStatus s) {
    switch (s) {
      case RentalListingStatus.pendingApproval:
        return "Pending approval";
      case RentalListingStatus.approved:
        return "Approved";
      case RentalListingStatus.rejected:
        return "Rejected";
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Luxury Car Rental Listings")),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<RentalListing>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return ListView(
                children: [
                  const SizedBox(height: 80),
                  Center(child: Text('Failed to load listings: ${snapshot.error}', textAlign: TextAlign.center)),
                  const SizedBox(height: 12),
                  Center(child: TextButton(onPressed: _refresh, child: const Text('Retry'))),
                ],
              );
            }
            final listings = snapshot.data ?? const [];
            if (listings.isEmpty) {
              return ListView(
                children: const [
                  SizedBox(height: 80),
                  Center(child: Text('No rental listings yet.', style: TextStyle(color: Colors.black54))),
                ],
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: listings.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final l = listings[i];
                final mutating = _mutatingIds.contains(l.id);
                return Container(
                  padding: const EdgeInsets.all(14),
                  decoration: AppComponents.cardDecoration(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(child: Text(l.vehicle, style: const TextStyle(fontWeight: FontWeight.w600))),
                          AppComponents.badge(_statusLabel(l.status), color: _statusColor(l.status)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text("Owner: ${l.ownerName} · ${l.location}", style: const TextStyle(fontSize: 12, color: Colors.black54)),
                      const SizedBox(height: 6),
                      Text("₦${l.dailyRate.toStringAsFixed(0)} / day", style: const TextStyle(fontWeight: FontWeight.w700)),
                      if (l.status == RentalListingStatus.pendingApproval) ...[
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(child: AppComponents.outlineButton(text: mutating ? "…" : "Reject", color: AppColors.danger, onPressed: mutating ? null : () => _decide(l, 'REJECTED'))),
                            const SizedBox(width: 10),
                            Expanded(child: AppComponents.primaryButton(text: mutating ? "…" : "Approve", onPressed: mutating ? null : () => _decide(l, 'APPROVED'))),
                          ],
                        ),
                      ],
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
