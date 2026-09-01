import 'package:flutter/material.dart';
import 'package:ravelgo_admin/theme/app_theme.dart';

class LoyaltyProgramScreen extends StatelessWidget {
  const LoyaltyProgramScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tiers = [
      ("Bronze", "0-19 trips", "Standard support"),
      ("Silver", "20-49 trips", "5% ride discount, priority matching"),
      ("Gold", "50-99 trips", "10% ride discount, free upgrades"),
      ("Platinum", "100+ trips", "15% ride discount, partner perks, dedicated support"),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text("Loyalty & Promotions")),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          AppComponents.sectionTitle("Gamified loyalty tiers"),
          ...tiers.map((t) => Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: AppComponents.cardDecoration(),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(color: AppColors.border.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(10)),
                      child: const Icon(Icons.emoji_events_outlined, color: AppColors.textSecondary),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("${t.$1} · ${t.$2}", style: const TextStyle(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 4),
                          Text(t.$3, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                        ],
                      ),
                    ),
                  ],
                ),
              )),
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
                    onTap: () {
                      showDialog(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Active campaigns'),
                          content: const Text(
                              '• RAVEL20 - 20% off first ride (2,431 uses)\n'
                              '• DRIVE5K - ₦5,000 driver referral bonus (312 uses)\n'
                              '• WKND10 - 10% off weekend rides (897 uses)'),
                          actions: [
                            TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('Close')),
                          ],
                        ),
                      );
                    }),
                AppComponents.divider(),
                AppComponents.tile(
                    title: "Create new promo code",
                    leading: Icons.add_circle_outline,
                    onTap: () async {
                      final controller = TextEditingController();
                      final code = await showDialog<String>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('New promo code'),
                          content: TextField(
                            controller: controller,
                            textCapitalization: TextCapitalization.characters,
                            decoration: const InputDecoration(hintText: 'e.g. SEPT15'),
                          ),
                          actions: [
                            TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('Cancel')),
                            TextButton(
                                onPressed: () =>
                                    Navigator.pop(context, controller.text.trim().toUpperCase()),
                                child: const Text('Create')),
                          ],
                        ),
                      );
                      if (code != null && code.isNotEmpty && context.mounted) {
                        // LOCAL STATE ONLY: recorded for this session; the
                        // promotions API is the integration point.
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(
                              'Promo code $code recorded locally (promotions service not connected)'),
                        ));
                      }
                    }),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
