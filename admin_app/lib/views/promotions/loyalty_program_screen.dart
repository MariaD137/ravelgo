import 'package:flutter/material.dart';
import 'package:ravelgo_admin/services/api/api_client.dart';
import 'package:ravelgo_admin/services/api/loyalty_api.dart';
import 'package:ravelgo_admin/theme/app_theme.dart';

class LoyaltyProgramScreen extends StatefulWidget {
  final LoyaltyApi? loyaltyApi;
  const LoyaltyProgramScreen({super.key, this.loyaltyApi});

  @override
  State<LoyaltyProgramScreen> createState() => _LoyaltyProgramScreenState();
}

class _LoyaltyProgramScreenState extends State<LoyaltyProgramScreen> {
  late final LoyaltyApi _api = widget.loyaltyApi ?? LoyaltyApi(ApiClient());
  late Future<(List<Map<String, dynamic>>, List<Map<String, dynamic>>)> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<(List<Map<String, dynamic>>, List<Map<String, dynamic>>)> _load() async {
    final results = await Future.wait([_api.listTiers(), _api.listPromotions()]);
    return (results[0], results[1]);
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  Future<void> _createPromotion() async {
    final codeController = TextEditingController();
    final descriptionController = TextEditingController();
    final discountController = TextEditingController();
    final created = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New promo code'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: codeController, decoration: const InputDecoration(labelText: 'Code')),
            TextField(controller: descriptionController, decoration: const InputDecoration(labelText: 'Description')),
            TextField(controller: discountController, decoration: const InputDecoration(labelText: 'Discount %'), keyboardType: TextInputType.number),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              final discount = double.tryParse(discountController.text);
              if (codeController.text.trim().isEmpty || descriptionController.text.trim().isEmpty || discount == null) {
                return;
              }
              try {
                await _api.createPromotion(
                  code: codeController.text.trim(),
                  description: descriptionController.text.trim(),
                  discountPercent: discount,
                );
                if (context.mounted) Navigator.pop(context, true);
              } catch (err) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to create promotion: $err')));
                }
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
    codeController.dispose();
    descriptionController.dispose();
    discountController.dispose();
    if (created == true) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Loyalty & Promotions")),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<(List<Map<String, dynamic>>, List<Map<String, dynamic>>)>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return ListView(
                children: [
                  const SizedBox(height: 80),
                  Center(child: Text('Failed to load: ${snapshot.error}', textAlign: TextAlign.center)),
                  const SizedBox(height: 12),
                  Center(child: TextButton(onPressed: _refresh, child: const Text('Retry'))),
                ],
              );
            }
            final (tiers, promotions) = snapshot.data!;
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                AppComponents.sectionTitle("Loyalty tiers"),
                if (tiers.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text("No loyalty tiers configured.", style: TextStyle(color: Colors.black54)),
                  ),
                ...tiers.map((t) => Container(
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
                                Text("${t['name']} · ${t['minCompletedTrips']}+ trips", style: const TextStyle(fontWeight: FontWeight.w700)),
                                const SizedBox(height: 4),
                                Text(
                                  "${(t['discountPercent'] as num).toStringAsFixed(0)}% discount${t['perks'] != null ? ' · ${t['perks']}' : ''}",
                                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    )),
                const SizedBox(height: 16),
                AppComponents.sectionTitle("Promotions"),
                if (promotions.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text("No active promotions.", style: TextStyle(color: Colors.black54)),
                  ),
                Container(
                  decoration: AppComponents.cardDecoration(),
                  child: Column(
                    children: [
                      for (var i = 0; i < promotions.length; i++) ...[
                        if (i > 0) AppComponents.divider(),
                        AppComponents.tile(
                          title: promotions[i]['code'] as String,
                          subtitle: '${promotions[i]['description']} · ${(promotions[i]['discountPercent'] as num).toStringAsFixed(0)}% off · ${promotions[i]['redemptionCount']} redeemed',
                          leading: Icons.campaign_outlined,
                          onTap: () {},
                        ),
                      ],
                      if (promotions.isNotEmpty) AppComponents.divider(),
                      AppComponents.tile(title: "Create new promo code", leading: Icons.add_circle_outline, onTap: _createPromotion),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
