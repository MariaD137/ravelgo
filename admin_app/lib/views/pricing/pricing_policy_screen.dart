import 'package:flutter/material.dart';
import 'package:ravelgo_admin/config/currency.dart';
import 'package:ravelgo_admin/services/admin_api.dart';
import 'package:ravelgo_admin/services/api_client.dart';
import 'package:ravelgo_admin/theme/app_theme.dart';

/// Cancellation fees, free-waiting windows, per-minute waiting charges,
/// surge bounds, and the delivery package-size surcharge table — the
/// PricingPolicy singleton row (backend/src/lib/pricing-policy.ts) already
/// drives every trip/delivery's actual charges, but had no admin screen at
/// all: an operator could only change these by editing the database
/// directly. Every value here is read from and written straight back to
/// that real row — nothing local-only.
class PricingPolicyScreen extends StatefulWidget {
  const PricingPolicyScreen({super.key});

  @override
  State<PricingPolicyScreen> createState() => _PricingPolicyScreenState();
}

class _PricingPolicyScreenState extends State<PricingPolicyScreen> {
  bool _loading = true;
  String? _error;
  PricingPolicy? _policy;
  bool _readOnly = false;

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
      final policy = await AdminApi.pricingPolicy();
      if (!mounted) return;
      setState(() {
        _policy = policy;
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

  Future<void> _editNumber({
    required String title,
    required String description,
    required double current,
    required String suffix,
    bool isInt = false,
    required Future<PricingPolicy> Function(double value) apply,
  }) async {
    final ctrl = TextEditingController(text: isInt ? current.toStringAsFixed(0) : current.toString());
    final result = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(description, style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
            const SizedBox(height: 14),
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: TextInputType.numberWithOptions(decimal: !isInt),
              decoration: InputDecoration(suffixText: suffix, border: const OutlineInputBorder()),
            ),
          ],
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
    if (result == null || result < 0) return;
    try {
      final updated = await apply(result);
      if (!mounted) return;
      setState(() {
        _policy = updated;
        _readOnly = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pricing policy updated.')));
    } catch (e) {
      if (!mounted) return;
      final is403 = e is ApiException && e.statusCode == 403;
      if (is403) setState(() => _readOnly = true);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(is403
            ? 'Only a Super Admin can change pricing policy. You can still view the current values.'
            : (e is ApiException ? e.message : e.toString())),
      ));
    }
  }

  Future<void> _editSurcharge(String size, double current) async {
    final ctrl = TextEditingController(text: current.toStringAsFixed(0));
    final result = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$size package surcharge'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(prefixText: Currency.symbol, border: const OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, double.tryParse(ctrl.text.trim())), child: const Text('Save')),
        ],
      ),
    );
    if (result == null || result < 0 || _policy == null) return;
    final updatedMap = Map<String, double>.of(_policy!.packageSizeSurcharge)..[size] = result;
    try {
      final updated = await AdminApi.updatePricingPolicy(packageSizeSurcharge: updatedMap);
      if (!mounted) return;
      setState(() {
        _policy = updated;
        _readOnly = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pricing policy updated.')));
    } catch (e) {
      if (!mounted) return;
      final is403 = e is ApiException && e.statusCode == 403;
      if (is403) setState(() => _readOnly = true);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(is403
            ? 'Only a Super Admin can change pricing policy. You can still view the current values.'
            : (e is ApiException ? e.message : e.toString())),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pricing Policy')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (_error != null ? _errView() : _body()),
    );
  }

  Widget _errView() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.danger)),
            TextButton(onPressed: _load, child: const Text('Try again')),
          ]),
        ),
      );

  Widget _body() {
    final p = _policy!;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(color: AppColors.primaryContainer, borderRadius: BorderRadius.circular(AppRadius.medium)),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, size: 18, color: AppColors.textSecondary),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'These values already drive every trip and delivery\'s real cancellation fees, free-waiting '
                    'windows, waiting charges, surge bounds, and delivery package surcharge — this is the only '
                    'admin screen for them, replacing direct database edits.',
                    style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                  ),
                ),
              ],
            ),
          ),
          if (_readOnly)
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(color: AppColors.warning.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(AppRadius.medium)),
              child: const Row(
                children: [
                  Icon(Icons.lock_outline, size: 18, color: AppColors.warning),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'View-only for your role. Only a Super Admin can change pricing policy.',
                      style: TextStyle(fontSize: 12.5, color: AppColors.warning, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          _section('Ride cancellation', [
            _row('Grace period', '${p.rideCancellationGraceSec}s', () => _editNumber(
                  title: 'Ride cancellation grace period',
                  description: 'A rider who cancels within this many seconds of requesting pays no fee.',
                  current: p.rideCancellationGraceSec.toDouble(),
                  suffix: 's',
                  isInt: true,
                  apply: (v) => AdminApi.updatePricingPolicy(rideCancellationGraceSec: v.round()),
                )),
            _row('Cancellation fee', Currency.format(p.rideCancellationFee, decimals: 0), () => _editNumber(
                  title: 'Ride cancellation fee',
                  description: 'Charged when a rider cancels after the grace period has passed.',
                  current: p.rideCancellationFee,
                  suffix: '',
                  apply: (v) => AdminApi.updatePricingPolicy(rideCancellationFee: v),
                )),
          ]),
          _section('Ride waiting charges', [
            _row('Free waiting window', '${p.rideWaitingFreeSec}s', () => _editNumber(
                  title: 'Ride free-waiting window',
                  description: 'How long a driver waits at pickup before waiting charges start.',
                  current: p.rideWaitingFreeSec.toDouble(),
                  suffix: 's',
                  isInt: true,
                  apply: (v) => AdminApi.updatePricingPolicy(rideWaitingFreeSec: v.round()),
                )),
            _row('Per-minute charge', Currency.format(p.rideWaitingPerMinute, decimals: 0), () => _editNumber(
                  title: 'Ride waiting charge per minute',
                  description: '100% driver-compensation — RavelGo takes no commission on this.',
                  current: p.rideWaitingPerMinute,
                  suffix: '',
                  apply: (v) => AdminApi.updatePricingPolicy(rideWaitingPerMinute: v),
                )),
            _row('Maximum charge', Currency.format(p.rideWaitingMaxFee, decimals: 0), () => _editNumber(
                  title: 'Ride waiting charge cap',
                  description: 'The most a rider can be charged for waiting time on one trip.',
                  current: p.rideWaitingMaxFee,
                  suffix: '',
                  apply: (v) => AdminApi.updatePricingPolicy(rideWaitingMaxFee: v),
                )),
          ]),
          _section('Delivery', [
            _row('Cancellation grace period', '${p.deliveryCancellationGraceSec}s', () => _editNumber(
                  title: 'Delivery cancellation grace period',
                  description: 'A sender who cancels within this many seconds of requesting pays no fee.',
                  current: p.deliveryCancellationGraceSec.toDouble(),
                  suffix: 's',
                  isInt: true,
                  apply: (v) => AdminApi.updatePricingPolicy(deliveryCancellationGraceSec: v.round()),
                )),
            _row('Cancellation fee', Currency.format(p.deliveryCancellationFee, decimals: 0), () => _editNumber(
                  title: 'Delivery cancellation fee',
                  description: 'Charged when a sender cancels after the grace period has passed.',
                  current: p.deliveryCancellationFee,
                  suffix: '',
                  apply: (v) => AdminApi.updatePricingPolicy(deliveryCancellationFee: v),
                )),
            _row('Additional stop fee', Currency.format(p.additionalStopFee, decimals: 0), () => _editNumber(
                  title: 'Additional stop fee',
                  description: 'Added per extra stop on a delivery route.',
                  current: p.additionalStopFee,
                  suffix: '',
                  apply: (v) => AdminApi.updatePricingPolicy(additionalStopFee: v),
                )),
          ]),
          _section('Surge bounds', [
            _row('Minimum multiplier', '${p.surgeMinMultiplier}x', () => _editNumber(
                  title: 'Surge minimum multiplier',
                  description: 'The lowest a SurgeZone multiplier may be set to.',
                  current: p.surgeMinMultiplier,
                  suffix: 'x',
                  apply: (v) => AdminApi.updatePricingPolicy(surgeMinMultiplier: v),
                )),
            _row('Maximum multiplier', '${p.surgeMaxMultiplier}x', () => _editNumber(
                  title: 'Surge maximum multiplier',
                  description: 'The highest a SurgeZone multiplier may be set to.',
                  current: p.surgeMaxMultiplier,
                  suffix: 'x',
                  apply: (v) => AdminApi.updatePricingPolicy(surgeMaxMultiplier: v),
                )),
          ]),
          _section('Delivery package surcharge', [
            for (final size in ['SMALL', 'MEDIUM', 'LARGE'])
              _row(size, Currency.format(p.packageSizeSurcharge[size] ?? 0, decimals: 0),
                  () => _editSurcharge(size, p.packageSizeSurcharge[size] ?? 0)),
          ]),
        ],
      ),
    );
  }

  Widget _section(String title, List<Widget> rows) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: 8),
          Container(decoration: AppComponents.cardDecoration(), child: Column(children: rows)),
        ],
      ),
    );
  }

  Widget _row(String label, String value, VoidCallback onEdit) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13.5))),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(width: 6),
          IconButton(icon: const Icon(Icons.edit_outlined, size: 18), onPressed: onEdit, tooltip: 'Edit $label'),
        ],
      ),
    );
  }
}
