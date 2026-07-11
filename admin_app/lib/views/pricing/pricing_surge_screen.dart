import 'package:flutter/material.dart';
import 'package:ravelgo_admin/theme/app_theme.dart';

class PricingSurgeScreen extends StatefulWidget {
  const PricingSurgeScreen({super.key});

  @override
  State<PricingSurgeScreen> createState() => _PricingSurgeScreenState();
}

class _PricingSurgeScreenState extends State<PricingSurgeScreen> {
  double _surgeMultiplier = 1.4;
  bool _trafficDiscountEnabled = true;

  static const _zones = [
    ("Victoria Island", 1.6),
    ("Lekki Phase 1", 1.3),
    ("Ikeja", 1.0),
    ("Yaba", 1.1),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Pricing & Surge")),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: AppComponents.cardDecoration(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Base fare", style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                const TextField(decoration: InputDecoration(prefixText: "₦ ", hintText: "500", border: OutlineInputBorder())),
                const SizedBox(height: 8),
                const TextField(decoration: InputDecoration(prefixText: "₦ ", hintText: "150 / km", border: OutlineInputBorder())),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: AppComponents.cardDecoration(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("Global surge multiplier", style: TextStyle(fontWeight: FontWeight.w700)),
                    Text("${_surgeMultiplier.toStringAsFixed(1)}x", style: const TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
                Slider(
                  value: _surgeMultiplier,
                  min: 1.0,
                  max: 3.0,
                  divisions: 20,
                  activeColor: AppColors.primaryDark,
                  onChanged: (v) => setState(() => _surgeMultiplier = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text("Real-time traffic-based fare discounts"),
                  subtitle: const Text("Apply discounts during low-traffic / off-peak hours", style: TextStyle(fontSize: 12)),
                  value: _trafficDiscountEnabled,
                  onChanged: (v) => setState(() => _trafficDiscountEnabled = v),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          AppComponents.sectionTitle("Surge by zone"),
          ..._zones.map((z) => Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: AppComponents.cardDecoration(),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(z.$1),
                    AppComponents.badge("${z.$2}x", color: z.$2 > 1.2 ? AppColors.warning : AppColors.success),
                  ],
                ),
              )),
          const SizedBox(height: 10),
          AppComponents.primaryButton(text: "Save pricing rules", onPressed: () => Navigator.pop(context)),
        ],
      ),
    );
  }
}
