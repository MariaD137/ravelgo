import 'package:flutter/material.dart';
import 'package:ravelgo_admin/config/currency.dart';
import 'package:ravelgo_admin/services/admin_api.dart';
import 'package:ravelgo_admin/services/api_client.dart';
import 'package:ravelgo_admin/theme/app_theme.dart';

const _vehicleIcons = {
  'BIKE': Icons.two_wheeler_outlined,
  'CAR': Icons.directions_car_outlined,
  'SUV': Icons.directions_car_filled_outlined,
  'VAN': Icons.airport_shuttle_outlined,
};

/// Delivery vehicle rate CRUD — the fixed "Vehicle | Base | Per KM |
/// Commission" reference table (Bike/Car/SUV/Van). There is always exactly
/// one row per class, seeded server-side; this screen only ever PATCHes an
/// existing row, no create/delete affordance is offered.
class DeliveryVehicleRatesScreen extends StatefulWidget {
  const DeliveryVehicleRatesScreen({super.key});

  @override
  State<DeliveryVehicleRatesScreen> createState() => _DeliveryVehicleRatesScreenState();
}

class _DeliveryVehicleRatesScreenState extends State<DeliveryVehicleRatesScreen> {
  bool _loading = true;
  String? _error;
  List<DeliveryVehicleRate> _rates = const [];

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
      final rates = await AdminApi.deliveryVehicleRates();
      if (!mounted) return;
      setState(() {
        _rates = rates;
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

  Future<void> _edit(DeliveryVehicleRate rate) async {
    final nameCtrl = TextEditingController(text: rate.name);
    final feeCtrl = TextEditingController(text: rate.initialFee.toStringAsFixed(0));
    final perKmCtrl = TextEditingController(text: rate.perKm.toStringAsFixed(0));
    final commissionCtrl =
        TextEditingController(text: rate.commissionRate == null ? '' : (rate.commissionRate! * 100).toStringAsFixed(1));
    var active = rate.active;
    final sym = Currency.symbol;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Edit ${rate.vehicleClass}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Display name', border: OutlineInputBorder())),
                const SizedBox(height: 10),
                TextField(
                  controller: feeCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(prefixText: '$sym ', labelText: 'Base / initial fee', border: const OutlineInputBorder()),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: perKmCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(prefixText: '$sym ', labelText: 'Per km', border: const OutlineInputBorder()),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: commissionCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Commission override (optional)',
                    suffixText: '%',
                    helperText: 'Leave blank to inherit the platform DELIVERY commission rate',
                    border: OutlineInputBorder(),
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Active'),
                  value: active,
                  onChanged: (v) => setDialogState(() => active = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (result != true) return;

    final name = nameCtrl.text.trim();
    final fee = double.tryParse(feeCtrl.text.trim());
    final perKm = double.tryParse(perKmCtrl.text.trim());
    final commissionText = commissionCtrl.text.trim();
    final commissionPercent = commissionText.isEmpty ? null : double.tryParse(commissionText);
    if (name.isEmpty || fee == null || perKm == null || fee < 0 || perKm < 0) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a name and non-negative fee/per-km.')));
      return;
    }
    if (commissionText.isNotEmpty && (commissionPercent == null || commissionPercent < 0 || commissionPercent > 100)) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Commission override must be a percentage between 0 and 100, or left blank.')));
      }
      return;
    }

    try {
      final updated = await AdminApi.updateDeliveryVehicleRate(
        rate.vehicleClass,
        name: name,
        initialFee: fee,
        perKm: perKm,
        commissionRate: commissionPercent == null ? null : commissionPercent / 100,
        clearCommissionRate: commissionPercent == null,
        active: active,
      );
      if (!mounted) return;
      setState(() => _rates = [for (final r in _rates) if (r.vehicleClass == rate.vehicleClass) updated else r]);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${rate.vehicleClass} rate updated.')));
    } catch (e) {
      if (!mounted) return;
      final msg = e is ApiException && e.statusCode == 403
          ? 'You don\'t have permission to change delivery vehicle rates.'
          : (e is ApiException ? e.message : e.toString());
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Delivery Vehicle Rates')),
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
    final sym = Currency.symbol;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: AppColors.primaryContainer,
              borderRadius: BorderRadius.circular(AppRadius.medium),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline, size: 18, color: AppColors.textSecondary),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'A fixed set of 4 vehicle classes — edit their rate cards below. New classes aren\'t supported here.',
                    style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                  ),
                ),
              ],
            ),
          ),
          ..._rates.map((r) => Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: AppComponents.cardDecoration(borderColor: r.active ? null : AppColors.border),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceElevated,
                            borderRadius: BorderRadius.circular(AppRadius.small),
                          ),
                          child: Icon(_vehicleIcons[r.vehicleClass] ?? Icons.local_shipping_outlined, color: AppColors.textSecondary),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(r.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                              Text(r.vehicleClass, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                            ],
                          ),
                        ),
                        if (!r.active) AppComponents.badge('Inactive', color: AppColors.textMuted),
                        IconButton(icon: const Icon(Icons.edit_outlined, size: 20), onPressed: () => _edit(r)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    // "Vehicle | Base | Per KM | Commission" — the spec's own
                    // reference table layout.
                    Table(
                      columnWidths: const {0: FlexColumnWidth(1), 1: FlexColumnWidth(1), 2: FlexColumnWidth(1)},
                      children: [
                        const TableRow(children: [
                          Padding(padding: EdgeInsets.only(bottom: 2), child: Text('Base', style: TextStyle(fontSize: 10.5, color: AppColors.textMuted, fontWeight: FontWeight.w600))),
                          Padding(padding: EdgeInsets.only(bottom: 2), child: Text('Per km', style: TextStyle(fontSize: 10.5, color: AppColors.textMuted, fontWeight: FontWeight.w600))),
                          Padding(padding: EdgeInsets.only(bottom: 2), child: Text('Commission', style: TextStyle(fontSize: 10.5, color: AppColors.textMuted, fontWeight: FontWeight.w600))),
                        ]),
                        TableRow(children: [
                          Text('$sym${r.initialFee.toStringAsFixed(0)}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                          Text('$sym${r.perKm.toStringAsFixed(0)}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                          Text(
                            r.commissionRate == null ? 'Default' : '${(r.commissionRate! * 100).toStringAsFixed(1)}%',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: r.commissionRate == null ? AppColors.textSecondary : AppColors.textPrimary,
                            ),
                          ),
                        ]),
                      ],
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}
