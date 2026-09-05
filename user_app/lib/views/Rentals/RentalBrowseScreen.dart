import 'package:flutter/material.dart';
import 'package:ravelgo_user_app/config/currency.dart';
import 'package:ravelgo_user_app/services/api_client.dart';
import 'package:ravelgo_user_app/services/rental_api.dart';
import 'package:ravelgo_user_app/theme/app_theme.dart';
import 'package:ravelgo_user_app/views/Rentals/RentalDetailScreen.dart';

/// Browse real, admin-approved vehicles listed for rental by drivers. Backed
/// by GET /api/rentals — no hardcoded cars.
class RentalBrowseScreen extends StatefulWidget {
  const RentalBrowseScreen({super.key});

  @override
  State<RentalBrowseScreen> createState() => _RentalBrowseScreenState();
}

class _RentalBrowseScreenState extends State<RentalBrowseScreen> {
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
      final listings = await RentalApi.browse();
      if (!mounted) return;
      setState(() {
        _listings = listings;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Rent a car')),
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
              Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.error)),
              const SizedBox(height: 8),
              TextButton(onPressed: _load, child: const Text('Try again')),
            ],
          ),
        ),
      );
    }
    if (_listings.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.directions_car_outlined, size: 40, color: AppColors.textMuted),
              SizedBox(height: 12),
              Text('No vehicles available to rent right now.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondary)),
              Text('Check back soon.', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _listings.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          final l = _listings[i];
          return InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => RentalDetailScreen(listingId: l.id))),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(color: AppColors.surfaceElevated, borderRadius: BorderRadius.circular(10)),
                    child: const Icon(Icons.directions_car, color: AppColors.primaryDark, size: 30),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l.vehicle?.label.isNotEmpty == true ? l.vehicle!.label : 'Vehicle',
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Text(l.location, style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
                        const SizedBox(height: 4),
                        Text('${Currency.format(l.dailyRate, decimals: 0)} / day',
                            style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.primaryDark)),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: AppColors.textMuted),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
