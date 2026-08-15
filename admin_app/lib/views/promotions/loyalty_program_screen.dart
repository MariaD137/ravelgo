import 'package:flutter/material.dart';
import 'package:ravelgo_admin/services/api_client.dart';
import 'package:ravelgo_admin/theme/app_theme.dart';

class LoyaltyProgramScreen extends StatefulWidget {
  const LoyaltyProgramScreen({super.key});

  @override
  State<LoyaltyProgramScreen> createState() => _LoyaltyProgramScreenState();
}

class _LoyaltyProgramScreenState extends State<LoyaltyProgramScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _tiers = [];

  // Fallback tiers if API doesn't return any
  static const _defaultTiers = [
    {"name": "Bronze", "range": "0-19 trips", "perks": "Standard support"},
    {"name": "Silver", "range": "20-49 trips", "perks": "5% ride discount, priority matching"},
    {"name": "Gold", "range": "50-99 trips", "perks": "10% ride discount, free upgrades"},
    {"name": "Platinum", "range": "100+ trips", "perks": "15% ride discount, partner perks, dedicated support"},
  ];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final response = await ApiClient().get('/loyalty/tiers');
      final data = response as Map<String, dynamic>;
      if (!mounted) return;

      final tiers = List<Map<String, dynamic>>.from(data['data'] ?? data['tiers'] ?? []);

      setState(() {
        _tiers = tiers;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      // On error, show default tiers with error banner
      setState(() {
        _tiers = _defaultTiers.map((t) => Map<String, dynamic>.from(t)).toList();
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _showComingSoon(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$feature: Feature coming soon')),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text("Loyalty & Promotions")),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text("Loyalty & Promotions")),
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (_error != null)
              Container(
                padding: const EdgeInsets.all(14),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(color: AppColors.warning.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                child: Text(
                  "Could not load tiers from server. Showing default configuration.",
                  style: TextStyle(fontSize: 12.5, color: AppColors.warning),
                ),
              ),
            AppComponents.sectionTitle("Gamified loyalty tiers"),
            ..._tiers.map((t) {
              final name = t['name'] as String? ?? '';
              final range = t['range'] as String? ?? t['tripRange'] as String? ?? '';
              final perks = t['perks'] as String? ?? t['benefits'] as String? ?? '';

              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: AppComponents.cardDecoration(),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(10)),
                      child: const Icon(Icons.emoji_events_outlined, color: AppColors.primaryDark),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("$name · $range", style: const TextStyle(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 4),
                          Text(perks, style: const TextStyle(fontSize: 12, color: Colors.black54)),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 16),
            AppComponents.sectionTitle("Referral codes"),
            Container(
              decoration: AppComponents.cardDecoration(),
              child: Column(
                children: [
                  AppComponents.tile(
                    title: "Active referral campaigns",
                    subtitle: "3 campaigns running",
                    leading: Icons.campaign_outlined,
                    onTap: () => _showComingSoon('Referral campaigns'),
                  ),
                  AppComponents.divider(),
                  AppComponents.tile(
                    title: "Create new promo code",
                    leading: Icons.add_circle_outline,
                    onTap: () => _showComingSoon('Promo code creation'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
