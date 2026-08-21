import 'package:flutter/material.dart';
import 'package:ravelgo_admin/services/api_client.dart';
import 'package:ravelgo_admin/theme/app_theme.dart';

class PricingSurgeScreen extends StatefulWidget {
  const PricingSurgeScreen({super.key});

  @override
  State<PricingSurgeScreen> createState() => _PricingSurgeScreenState();
}

class _PricingSurgeScreenState extends State<PricingSurgeScreen> {
  bool _loading = true;
  String? _error;
  bool _saving = false;

  double _surgeMultiplier = 1.4;
  bool _trafficDiscountEnabled = true;
  final _baseFareController = TextEditingController(text: '500');
  final _perKmController = TextEditingController(text: '150');
  List<Map<String, dynamic>> _zones = [];

  // Fallback zones
  static const _defaultZones = [
    {"name": "Victoria Island", "multiplier": 1.6},
    {"name": "Lekki Phase 1", "multiplier": 1.3},
    {"name": "Ikeja", "multiplier": 1.0},
    {"name": "Yaba", "multiplier": 1.1},
  ];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _baseFareController.dispose();
    _perKmController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final response = await ApiClient().get('/pricing/surge-zones');
      final data = response as Map<String, dynamic>;
      if (!mounted) return;

      final zones = List<Map<String, dynamic>>.from(data['data'] ?? data['zones'] ?? []);
      final baseFare = data['baseFare'];
      final perKm = data['perKmRate'];
      final globalMultiplier = data['globalSurgeMultiplier'];
      final trafficDiscount = data['trafficDiscountEnabled'];

      setState(() {
        _zones = zones;
        if (baseFare != null) _baseFareController.text = baseFare.toString();
        if (perKm != null) _perKmController.text = perKm.toString();
        if (globalMultiplier != null) _surgeMultiplier = (globalMultiplier as num).toDouble();
        if (trafficDiscount != null) _trafficDiscountEnabled = trafficDiscount as bool;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _zones = _defaultZones.map((z) => Map<String, dynamic>.from(z)).toList();
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _savePricingRules() async {
    setState(() => _saving = true);
    try {
      await ApiClient().post('/pricing/rules', body: {
        'baseFare': double.tryParse(_baseFareController.text) ?? 500,
        'perKmRate': double.tryParse(_perKmController.text) ?? 150,
        'globalSurgeMultiplier': _surgeMultiplier,
        'trafficDiscountEnabled': _trafficDiscountEnabled,
      });
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pricing rules saved successfully')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save pricing rules: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text("Pricing & Surge")),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text("Pricing & Surge")),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (_error != null)
            Container(
              padding: const EdgeInsets.all(14),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(color: AppColors.warning.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
              child: Text(
                "Could not load surge zones from server. Showing default configuration.",
                style: TextStyle(fontSize: 12.5, color: AppColors.warning),
              ),
            ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: AppComponents.cardDecoration(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Base fare", style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                TextField(
                  controller: _baseFareController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(prefixText: "₦ ", hintText: "500", border: OutlineInputBorder()),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _perKmController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(prefixText: "₦ ", hintText: "150 / km", border: OutlineInputBorder()),
                ),
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
          ..._zones.map((z) {
            final name = z['name'] as String? ?? z['zone'] as String? ?? '';
            final multiplier = (z['multiplier'] as num? ?? z['surgeMultiplier'] as num? ?? 1.0).toDouble();

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: AppComponents.cardDecoration(),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(name),
                  AppComponents.badge("${multiplier.toStringAsFixed(1)}x", color: multiplier > 1.2 ? AppColors.warning : AppColors.success),
                ],
              ),
            );
          }),
          const SizedBox(height: 10),
          AppComponents.primaryButton(
            text: _saving ? "Saving..." : "Save pricing rules",
            onPressed: _saving ? null : _savePricingRules,
          ),
        ],
      ),
    );
  }
}
