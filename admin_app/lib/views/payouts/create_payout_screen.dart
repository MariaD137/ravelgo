import 'package:flutter/material.dart';
import 'package:ravelgo_admin/config/currency.dart';
import 'package:ravelgo_admin/services/admin_api.dart';
import 'package:ravelgo_admin/services/api_client.dart';
import 'package:ravelgo_admin/theme/app_theme.dart';

/// Admin: calculate and create a driver payout for a period
/// (POST /api/payouts/calculate, POST /api/payouts/create). Pops `true` when
/// a payout was created so the list screen can refresh.
class CreatePayoutScreen extends StatefulWidget {
  const CreatePayoutScreen({super.key});

  @override
  State<CreatePayoutScreen> createState() => _CreatePayoutScreenState();
}

class _CreatePayoutScreenState extends State<CreatePayoutScreen> {
  bool _loadingDrivers = true;
  String? _driversError;
  List<AdminDriver> _drivers = const [];
  AdminDriver? _selectedDriver;

  late final TextEditingController _periodController;
  final TextEditingController _overrideController = TextEditingController();

  bool _calculating = false;
  String? _calcError;
  PayoutCalculation? _calculation;

  bool _creating = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _periodController = TextEditingController(text: "${now.year}-${now.month.toString().padLeft(2, '0')}");
    _loadDrivers();
  }

  @override
  void dispose() {
    _periodController.dispose();
    _overrideController.dispose();
    super.dispose();
  }

  Future<void> _loadDrivers() async {
    setState(() {
      _loadingDrivers = true;
      _driversError = null;
    });
    try {
      // Every ACTIVE driver, across all pages — a picker must offer the whole
      // set, not whichever active drivers fell inside the first page.
      final drivers = await AdminApi.allDrivers(status: 'ACTIVE');
      if (!mounted) return;
      setState(() {
        _drivers = drivers;
        _loadingDrivers = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _driversError = e is ApiException ? e.message : e.toString();
        _loadingDrivers = false;
      });
    }
  }

  bool get _periodValid => RegExp(r'^\d{4}-\d{2}$').hasMatch(_periodController.text.trim());

  Future<void> _calculate() async {
    final driver = _selectedDriver;
    if (driver == null || !_periodValid) return;
    setState(() {
      _calculating = true;
      _calcError = null;
      _calculation = null;
    });
    try {
      final calc = await AdminApi.calculatePayout(driver.userId, _periodController.text.trim());
      if (!mounted) return;
      setState(() {
        _calculation = calc;
        _calculating = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _calcError = e is ApiException ? e.message : e.toString();
        _calculating = false;
      });
    }
  }

  Future<void> _create() async {
    final driver = _selectedDriver;
    if (driver == null || !_periodValid) return;
    final overrideText = _overrideController.text.trim();
    final override = overrideText.isEmpty ? null : double.tryParse(overrideText);
    if (overrideText.isNotEmpty && override == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a valid override amount')));
      return;
    }

    final amountText = override != null
        ? Currency.format(override, decimals: 0)
        : (_calculation != null ? Currency.format(_calculation!.netAmount, decimals: 0) : 'the calculated amount');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create this payout?'),
        content: Text(
          '${driver.name.isEmpty ? driver.email : driver.name} · $amountText for ${_periodController.text.trim()}.'
          '${override != null ? '\n\nThis is a manual override, not the calculated amount.' : ''}',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Create')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _creating = true);
    try {
      await AdminApi.createPayout(driver.userId, _periodController.text.trim(), amount: override);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      final msg = e is ApiException ? e.message : e.toString();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("New Payout"),
        actions: [
      // A-5: these screens load once and then sit on whatever they fetched.
      // Approvals, suspensions and payouts are worked in parallel by several
      // admins, so a stale detail view is a decision made on old facts; there
      // was no way to re-read it short of backing out and reopening.
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: (_loadingDrivers || _creating || _calculating) ? null : _loadDrivers,
          ),
        ],
      ),
      body: _loadingDrivers
          ? const Center(child: CircularProgressIndicator())
          : (_driversError != null ? _err() : _form()),
    );
  }

  Widget _err() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_driversError!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.danger)),
            TextButton(onPressed: _loadDrivers, child: const Text('Try again')),
          ]),
        ),
      );

  Widget _form() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text("Driver", style: TextStyle(color: AppColors.textSecondary)),
        const SizedBox(height: 6),
        if (_drivers.isEmpty)
          const Text("No active drivers to pay out.", style: TextStyle(color: AppColors.textSecondary))
        else
          DropdownButtonFormField<AdminDriver>(
            value: _selectedDriver,
            isExpanded: true,
            decoration: const InputDecoration(border: OutlineInputBorder()),
            hint: const Text('Select a driver'),
            items: _drivers
                .map((d) => DropdownMenuItem(value: d, child: Text(d.name.isEmpty ? d.email : d.name)))
                .toList(),
            onChanged: (d) => setState(() {
              _selectedDriver = d;
              _calculation = null;
              _calcError = null;
            }),
          ),
        const SizedBox(height: 20),
        const Text("Period (YYYY-MM)", style: TextStyle(color: AppColors.textSecondary)),
        const SizedBox(height: 6),
        TextField(
          controller: _periodController,
          decoration: const InputDecoration(border: OutlineInputBorder(), hintText: '2026-09'),
          onChanged: (_) => setState(() {
            _calculation = null;
            _calcError = null;
          }),
        ),
        const SizedBox(height: 16),
        AppComponents.outlineButton(
          text: _calculating ? "Calculating…" : "Calculate from trips",
          onPressed: (_selectedDriver == null || !_periodValid || _calculating) ? null : _calculate,
        ),
        if (_calcError != null) ...[
          const SizedBox(height: 10),
          Text(_calcError!, style: const TextStyle(color: AppColors.danger)),
        ],
        if (_calculation != null) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: AppComponents.cardDecoration(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _calcRow("Completed trips", "${_calculation!.tripsIncluded}"),
                _calcRow("Gross", Currency.format(_calculation!.grossAmount, decimals: 0)),
                _calcRow("Platform fee", "- ${Currency.format(_calculation!.platformFee, decimals: 0)}"),
                _calcRow("Subscription fee", "- ${Currency.format(_calculation!.subscriptionFee, decimals: 0)}"),
                const Divider(),
                _calcRow("Net payout", Currency.format(_calculation!.netAmount, decimals: 0), bold: true),
              ],
            ),
          ),
        ],
        const SizedBox(height: 24),
        const Text("Manual override amount (optional)", style: TextStyle(color: AppColors.textSecondary)),
        const SizedBox(height: 6),
        TextField(
          controller: _overrideController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: 'Leave blank to use the calculated net amount',
          ),
        ),
        const SizedBox(height: 24),
        AppComponents.outlineButton(
          text: _creating ? "Creating…" : "Create Payout",
          color: AppColors.primary,
          onPressed: (_selectedDriver == null || !_periodValid || _creating) ? null : _create,
        ),
      ],
    );
  }

  Widget _calcRow(String label, String value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: AppColors.textSecondary)),
          Text(value, style: TextStyle(fontWeight: bold ? FontWeight.w700 : FontWeight.w500)),
        ],
      ),
    );
  }
}
