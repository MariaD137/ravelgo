import 'package:flutter/material.dart';
import 'package:ravelgo_admin/services/admin_api.dart';
import 'package:ravelgo_admin/services/api_client.dart';
import 'package:ravelgo_admin/theme/app_theme.dart';
import 'package:ravelgo_admin/utils/date_utils.dart';

/// Real loyalty tiers (GET/POST /api/loyalty-tiers) and promotions
/// (GET/POST /api/promotions). There's no per-customer loyalty balance in
/// the backend — a rider's tier is computed on read from their completed
/// trip count — so none is shown here.
class LoyaltyProgramScreen extends StatefulWidget {
  const LoyaltyProgramScreen({super.key});

  @override
  State<LoyaltyProgramScreen> createState() => _LoyaltyProgramScreenState();
}

class _LoyaltyProgramScreenState extends State<LoyaltyProgramScreen> {
  bool _loading = true;
  String? _error;
  List<LoyaltyTier> _tiers = const [];
  List<Promotion> _promotions = const [];

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
      final results = await Future.wait([AdminApi.loyaltyTiers(), AdminApi.promotions()]);
      if (!mounted) return;
      setState(() {
        _tiers = results[0] as List<LoyaltyTier>;
        _promotions = results[1] as List<Promotion>;
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

  Future<void> _addTier() async {
    final nameController = TextEditingController();
    final tripsController = TextEditingController();
    final discountController = TextEditingController();
    final perksController = TextEditingController();

    final created = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New loyalty tier'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Name')),
              TextField(
                  controller: tripsController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Minimum completed trips')),
              TextField(
                  controller: discountController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Discount percent')),
              TextField(controller: perksController, decoration: const InputDecoration(labelText: 'Perks (optional)')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Create')),
        ],
      ),
    );
    if (created != true || !mounted) return;

    final minTrips = int.tryParse(tripsController.text.trim());
    final discount = double.tryParse(discountController.text.trim());
    if (nameController.text.trim().isEmpty || minTrips == null || discount == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a name, trip count and discount')));
      return;
    }

    try {
      await AdminApi.createLoyaltyTier(
        name: nameController.text.trim(),
        minCompletedTrips: minTrips,
        discountPercent: discount,
        perks: perksController.text.trim(),
      );
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e is ApiException ? e.message : e.toString())));
      }
    }
  }

  Future<void> _addPromotion() async {
    final codeController = TextEditingController();
    final descController = TextEditingController();
    final discountController = TextEditingController();
    final maxRedemptionsController = TextEditingController();

    final created = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New promotion'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                  controller: codeController,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(labelText: 'Code', hintText: 'e.g. SEPT15')),
              TextField(controller: descController, decoration: const InputDecoration(labelText: 'Description')),
              TextField(
                  controller: discountController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Discount percent')),
              TextField(
                  controller: maxRedemptionsController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Max redemptions (optional)')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Create')),
        ],
      ),
    );
    if (created != true || !mounted) return;

    final discount = double.tryParse(discountController.text.trim());
    if (codeController.text.trim().isEmpty || descController.text.trim().isEmpty || discount == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a code, description and discount')));
      return;
    }
    final maxRedemptions =
        maxRedemptionsController.text.trim().isEmpty ? null : int.tryParse(maxRedemptionsController.text.trim());

    try {
      await AdminApi.createPromotion(
        code: codeController.text.trim().toUpperCase(),
        description: descController.text.trim(),
        discountPercent: discount,
        maxRedemptions: maxRedemptions,
      );
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e is ApiException ? e.message : e.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Loyalty & Promotions")),
      body: _loading ? const Center(child: CircularProgressIndicator()) : (_error != null ? _err() : _body()),
    );
  }

  Widget _err() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.danger)),
            TextButton(onPressed: _load, child: const Text('Try again')),
          ]),
        ),
      );

  Widget _body() {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(20),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          AppComponents.sectionTitle("Loyalty tiers",
              trailing: IconButton(icon: const Icon(Icons.add), onPressed: _addTier)),
          if (_tiers.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text("No loyalty tiers yet.", style: TextStyle(color: AppColors.textSecondary)),
            )
          else
            ..._tiers.map((t) => Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: AppComponents.cardDecoration(),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                            color: AppColors.border.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(10)),
                        child: const Icon(Icons.emoji_events_outlined, color: AppColors.textSecondary),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("${t.name} · ${t.minCompletedTrips}+ trips",
                                style: const TextStyle(fontWeight: FontWeight.w700)),
                            const SizedBox(height: 4),
                            Text(
                                "${t.discountPercent.toStringAsFixed(0)}% ride discount"
                                "${t.perks?.isNotEmpty == true ? ' · ${t.perks}' : ''}",
                                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                          ],
                        ),
                      ),
                    ],
                  ),
                )),
          const SizedBox(height: 16),
          AppComponents.sectionTitle("Promotions",
              trailing: IconButton(icon: const Icon(Icons.add), onPressed: _addPromotion)),
          if (_promotions.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text("No active promotions.", style: TextStyle(color: AppColors.textSecondary)),
            )
          else
            ..._promotions.map((p) => Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: AppComponents.cardDecoration(),
                  child: AppComponents.tile(
                    title: "${p.code} · ${p.discountPercent.toStringAsFixed(0)}% off",
                    subtitle: "${p.description}"
                        "${p.maxRedemptions != null ? ' · ${p.redemptionCount}/${p.maxRedemptions} used' : ' · ${p.redemptionCount} used'}"
                        "${p.expiresAt != null ? ' · expires ${formatFriendlyDate(p.expiresAt!)}' : ''}",
                    leading: Icons.campaign_outlined,
                  ),
                )),
        ],
      ),
    );
  }
}
