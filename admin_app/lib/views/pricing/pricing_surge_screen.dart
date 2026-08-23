import 'package:flutter/material.dart';
import 'package:ravelgo_admin/services/api/api_client.dart';
import 'package:ravelgo_admin/services/api/pricing_api.dart';
import 'package:ravelgo_admin/theme/app_theme.dart';

class PricingSurgeScreen extends StatefulWidget {
  final PricingApi? pricingApi;
  const PricingSurgeScreen({super.key, this.pricingApi});

  @override
  State<PricingSurgeScreen> createState() => _PricingSurgeScreenState();
}

class _PricingSurgeScreenState extends State<PricingSurgeScreen> {
  late final PricingApi _api = widget.pricingApi ?? PricingApi(ApiClient());

  final _baseFareController = TextEditingController();
  final _perKmController = TextEditingController();
  final _perMinuteController = TextEditingController();

  Future<void>? _loadFuture;
  String? _activeRuleId;
  String? _activeRuleName;
  List<Map<String, dynamic>> _surgeZones = const [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadFuture = _load();
  }

  @override
  void dispose() {
    _baseFareController.dispose();
    _perKmController.dispose();
    _perMinuteController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final results = await Future.wait([_api.listPricingRules(), _api.listSurgeZones()]);
    final rules = results[0];
    final zones = results[1];
    final active = rules.isEmpty ? null : rules.firstWhere((r) => r['active'] == true, orElse: () => rules.first);
    _activeRuleId = active?['id'] as String?;
    _activeRuleName = active?['name'] as String?;
    _baseFareController.text = active == null ? '' : (active['baseFare'] as num).toString();
    _perKmController.text = active == null ? '' : (active['perKm'] as num).toString();
    _perMinuteController.text = active == null ? '' : (active['perMinute'] as num).toString();
    _surgeZones = zones;
  }

  Future<void> _save() async {
    final baseFare = double.tryParse(_baseFareController.text);
    final perKm = double.tryParse(_perKmController.text);
    final perMinute = double.tryParse(_perMinuteController.text);
    if (baseFare == null || perKm == null || perMinute == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter valid numbers for base fare, per km, and per minute.')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      if (_activeRuleId != null) {
        await _api.updatePricingRule(_activeRuleId!, baseFare: baseFare, perKm: perKm, perMinute: perMinute);
      } else {
        await _api.createPricingRule(name: 'Default', baseFare: baseFare, perKm: perKm, perMinute: perMinute);
      }
      if (!mounted) return;
      setState(() => _loadFuture = _load());
      await _loadFuture;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pricing rule saved')));
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to save pricing rule: $err')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Pricing & Surge")),
      body: FutureBuilder<void>(
        future: _loadFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Failed to load pricing: ${snapshot.error}'));
          }
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: AppComponents.cardDecoration(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _activeRuleName == null ? "Base fare (no active rule yet)" : "Base fare — $_activeRuleName",
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _baseFareController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(prefixText: "₦ ", labelText: "Base fare", border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _perKmController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(prefixText: "₦ ", labelText: "Per km", border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _perMinuteController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(prefixText: "₦ ", labelText: "Per minute", border: OutlineInputBorder()),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              AppComponents.sectionTitle("Surge by zone"),
              if (_surgeZones.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text("No surge zones configured.", style: TextStyle(color: Colors.black54)),
                ),
              ..._surgeZones.map((z) => Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: AppComponents.cardDecoration(),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('${z['name']} · ${z['location']}'),
                        AppComponents.badge(
                          '${(z['multiplier'] as num).toStringAsFixed(1)}x',
                          color: (z['multiplier'] as num) > 1.2 ? AppColors.warning : AppColors.success,
                        ),
                      ],
                    ),
                  )),
              const SizedBox(height: 10),
              AppComponents.primaryButton(text: _saving ? "Saving…" : "Save pricing rules", onPressed: _saving ? null : _save),
            ],
          );
        },
      ),
    );
  }
}
