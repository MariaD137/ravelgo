import 'package:flutter/material.dart';
import 'package:ravelgo_admin/config/currency.dart';
import 'package:ravelgo_admin/services/api_client.dart';
import 'package:ravelgo_admin/services/admin_api.dart';
import 'package:ravelgo_admin/theme/app_theme.dart';

/// Admin pricing & surge editor (P0 #11). Every value here comes from and is
/// written back to the real backend pricing endpoints — there is no local-only
/// state pretending to be saved. The base fare / per-km / per-minute drive the
/// server-authoritative fare used for every quote and trip.
class PricingSurgeScreen extends StatefulWidget {
  const PricingSurgeScreen({super.key});

  @override
  State<PricingSurgeScreen> createState() => _PricingSurgeScreenState();
}

class _PricingSurgeScreenState extends State<PricingSurgeScreen> {
  final _nameCtrl = TextEditingController();
  final _baseCtrl = TextEditingController();
  final _perKmCtrl = TextEditingController();
  final _perMinCtrl = TextEditingController();

  PricingRule? _rule; // the active rule being edited, if one exists
  List<SurgeZone> _zones = [];

  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _baseCtrl.dispose();
    _perKmCtrl.dispose();
    _perMinCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rules = await AdminApi.pricingRules();
      final zones = await AdminApi.surgeZones();
      if (!mounted) return;
      // Prefer the active rule; fall back to the most recent one.
      PricingRule? rule;
      for (final r in rules) {
        if (r.active) {
          rule = r;
          break;
        }
      }
      rule ??= rules.isNotEmpty ? rules.first : null;
      setState(() {
        _rule = rule;
        _nameCtrl.text = rule?.name ?? 'Standard';
        _baseCtrl.text = rule == null ? '' : rule.baseFare.toStringAsFixed(0);
        _perKmCtrl.text = rule == null ? '' : rule.perKm.toStringAsFixed(0);
        _perMinCtrl.text = rule == null ? '' : rule.perMinute.toStringAsFixed(0);
        _zones = zones;
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

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    final base = double.tryParse(_baseCtrl.text.trim());
    final perKm = double.tryParse(_perKmCtrl.text.trim());
    final perMin = double.tryParse(_perMinCtrl.text.trim());
    if (name.isEmpty || base == null || perKm == null || perMin == null) {
      setState(() => _error = 'Enter a name and numeric base fare, per-km and per-minute rates.');
      return;
    }
    if (base < 0 || perKm < 0 || perMin < 0) {
      setState(() => _error = 'Rates cannot be negative.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final rule = _rule;
      final saved = rule == null
          ? await AdminApi.createPricingRule(name: name, baseFare: base, perKm: perKm, perMinute: perMin)
          : await AdminApi.updatePricingRule(rule.id,
              name: name, baseFare: base, perKm: perKm, perMinute: perMin, active: true);
      if (!mounted) return;
      setState(() {
        _rule = saved;
        _saving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pricing rule saved.')));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException ? e.message : e.toString();
        _saving = false;
      });
    }
  }

  Future<void> _editZoneMultiplier(SurgeZone zone) async {
    final ctrl = TextEditingController(text: zone.multiplier.toStringAsFixed(2));
    final result = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Surge for ${zone.name}'),
        content: TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Multiplier (e.g. 1.5)', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, double.tryParse(ctrl.text.trim())),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result == null) return;
    if (result <= 0) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Multiplier must be positive.')));
      return;
    }
    try {
      final updated = await AdminApi.updateSurgeZone(zone.id, multiplier: result);
      if (!mounted) return;
      setState(() {
        _zones = [for (final z in _zones) if (z.id == zone.id) updated else z];
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${zone.name} surge updated.')));
    } catch (e) {
      if (!mounted) return;
      final msg = e is ApiException ? e.message : e.toString();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  Future<void> _addZone() async {
    final nameCtrl = TextEditingController();
    final locCtrl = TextEditingController();
    final multCtrl = TextEditingController(text: '1.5');
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New surge zone'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Name', border: OutlineInputBorder())),
            const SizedBox(height: 8),
            TextField(controller: locCtrl, decoration: const InputDecoration(labelText: 'Location', border: OutlineInputBorder())),
            const SizedBox(height: 8),
            TextField(
              controller: multCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Multiplier', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Create')),
        ],
      ),
    );
    if (ok != true) return;
    final name = nameCtrl.text.trim();
    final loc = locCtrl.text.trim();
    final mult = double.tryParse(multCtrl.text.trim());
    if (name.isEmpty || loc.isEmpty || mult == null || mult <= 0) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a name, location and positive multiplier.')));
      return;
    }
    try {
      final created = await AdminApi.createSurgeZone(name: name, location: loc, multiplier: mult);
      if (!mounted) return;
      setState(() => _zones = [created, ..._zones]);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Surge zone "$name" created.')));
    } catch (e) {
      if (!mounted) return;
      final msg = e is ApiException ? e.message : e.toString();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final sym = Currency.symbol;
    return Scaffold(
      appBar: AppBar(title: const Text("Pricing & Surge")),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  if (_error != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                          color: AppColors.error.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8)),
                      child: Text(_error!, style: const TextStyle(color: AppColors.error, fontSize: 13)),
                    ),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: AppComponents.cardDecoration(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("Active pricing rule", style: TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _nameCtrl,
                          decoration: const InputDecoration(labelText: 'Rule name', border: OutlineInputBorder()),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _baseCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(prefixText: "$sym ", labelText: "Base fare", border: const OutlineInputBorder()),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _perKmCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(prefixText: "$sym ", labelText: "Per km", border: const OutlineInputBorder()),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _perMinCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(prefixText: "$sym ", labelText: "Per minute", border: const OutlineInputBorder()),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  AppComponents.primaryButton(
                    text: _saving ? "Saving…" : "Save pricing rule",
                    onPressed: _saving ? null : _save,
                  ),
                  const SizedBox(height: 20),
                  AppComponents.sectionTitle("Surge by zone", trailing: TextButton(onPressed: _addZone, child: const Text("Add"))),
                  if (_zones.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text("No surge zones configured.", style: TextStyle(color: AppColors.textSecondary)),
                    ),
                  ..._zones.map((z) => Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(14),
                        decoration: AppComponents.cardDecoration(),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(z.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                                  Text(z.location, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                                ],
                              ),
                            ),
                            AppComponents.badge("${z.multiplier.toStringAsFixed(2)}x",
                                color: z.multiplier > 1.2 ? AppColors.warning : AppColors.success),
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, size: 20),
                              onPressed: () => _editZoneMultiplier(z),
                            ),
                          ],
                        ),
                      )),
                ],
              ),
            ),
    );
  }
}
