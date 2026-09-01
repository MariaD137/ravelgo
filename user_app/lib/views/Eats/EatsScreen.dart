import 'package:flutter/material.dart';
import 'package:ravelgo_user_app/services/api_client.dart';
import 'package:ravelgo_user_app/services/eats_api.dart';
import 'package:ravelgo_user_app/views/Eats/RestaurantDetailScreen.dart';
import 'package:ravelgo_user_app/theme/app_theme.dart';

/// Eats — browse restaurants (first screen of the food-delivery vertical).
class EatsScreen extends StatefulWidget {
  const EatsScreen({super.key});

  @override
  State<EatsScreen> createState() => _EatsScreenState();
}

class _EatsScreenState extends State<EatsScreen> {
  bool _loading = true;
  String? _error;
  List<Restaurant> _restaurants = const [];

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
      final list = await EatsApi.restaurants();
      if (!mounted) return;
      setState(() {
        _restaurants = list;
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
      appBar: AppBar(title: const Text('Eats')),
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
              TextButton(onPressed: _load, child: const Text('Try again')),
            ],
          ),
        ),
      );
    }
    if (_restaurants.isEmpty) {
      return const Center(
        child: Text('No restaurants nearby yet', style: TextStyle(color: AppColors.textSecondary)),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _restaurants.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, i) {
          final r = _restaurants[i];
          return InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => RestaurantDetailScreen(restaurantId: r.id, name: r.name)),
            ),
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceElevated,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.restaurant, color: AppColors.primaryDark),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(r.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                        const SizedBox(height: 2),
                        Text(
                          '${r.cuisine}${r.rating != null ? '  ·  ★ ${r.rating!.toStringAsFixed(1)}' : ''}',
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                        ),
                        const SizedBox(height: 2),
                        Text(r.address,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
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
