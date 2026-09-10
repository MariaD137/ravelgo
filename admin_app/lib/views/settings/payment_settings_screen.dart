import 'package:flutter/material.dart';
import 'package:ravelgo_admin/config/currency.dart';
import 'package:ravelgo_admin/services/admin_api.dart';
import 'package:ravelgo_admin/services/api_client.dart';
import 'package:ravelgo_admin/theme/app_theme.dart';

/// Payment rules: the cash cap and per-method on/off switches. Every value
/// shown here comes straight from the backend (GET /api/settings/payment) —
/// this screen never assumes it's allowed to write; a Super-Admin-only 403
/// from the backend is the real gate, this UI just avoids the round trip
/// for a change that would obviously fail.
class PaymentSettingsScreen extends StatefulWidget {
  const PaymentSettingsScreen({super.key});

  @override
  State<PaymentSettingsScreen> createState() => _PaymentSettingsScreenState();
}

class _PaymentSettingsScreenState extends State<PaymentSettingsScreen> {
  bool _loading = true;
  bool _saving = false;
  String? _error;
  PaymentSettings? _settings;
  final _limitController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _limitController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final settings = await AdminApi.paymentSettings();
      if (!mounted) return;
      setState(() {
        _settings = settings;
        _limitController.text = settings.cashPaymentLimit.toStringAsFixed(0);
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

  Future<void> _apply(Future<PaymentSettings> Function() action, {String? confirmTitle, String? confirmBody}) async {
    if (confirmTitle != null) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(confirmTitle),
          content: confirmBody == null ? null : Text(confirmBody),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Confirm')),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    setState(() => _saving = true);
    try {
      final updated = await action();
      if (!mounted) return;
      setState(() {
        _settings = updated;
        _limitController.text = updated.cashPaymentLimit.toStringAsFixed(0);
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Setting updated. Recorded in the audit log.')));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e is ApiException && e.statusCode == 403
              ? 'Only a Super Admin can change payment settings.'
              : (e is ApiException ? e.message : e.toString())),
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveLimit() async {
    final value = double.tryParse(_limitController.text.replaceAll(',', '').trim());
    if (value == null || value <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a valid amount.')));
      return;
    }
    final old = _settings?.cashPaymentLimit ?? 0;
    await _apply(
      () => AdminApi.updatePaymentSettings(cashPaymentLimit: value),
      confirmTitle: 'Change the cash payment limit?',
      confirmBody: 'From ${Currency.format(old, decimals: 0)} to ${Currency.format(value, decimals: 0)}. '
          'This changes what riders can pay in cash platform-wide, effective immediately.',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Payment Settings')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (_error != null ? _err() : _body()),
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
    final s = _settings!;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: AppComponents.cardDecoration(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Cash Payment Limit', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              const SizedBox(height: 4),
              const Text(
                'Cash is only offered to riders for a fare at or below this amount. Enforced by the backend on every '
                'charge, not just hidden in the app.',
                style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _limitController,
                      enabled: !_saving,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(prefixText: '₦ ', border: OutlineInputBorder(), isDense: true),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton(onPressed: _saving ? null : _saveLimit, child: const Text('Save')),
                ],
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
              const Text('Payment Methods', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              const SizedBox(height: 6),
              _methodSwitch(
                'Cash',
                'Pay the driver directly, up to the limit above.',
                s.cashPaymentEnabled,
                (v) => _apply(
                  () => AdminApi.updatePaymentSettings(cashPaymentEnabled: v),
                  confirmTitle: v ? 'Enable Cash payments?' : 'Disable Cash payments?',
                  confirmBody: v ? null : 'Riders will no longer be offered Cash for any fare, platform-wide.',
                ),
              ),
              _methodSwitch(
                'Card',
                'Paid securely via Paystack.',
                s.cardPaymentEnabled,
                (v) => _apply(
                  () => AdminApi.updatePaymentSettings(cardPaymentEnabled: v),
                  confirmTitle: v ? 'Enable Card payments?' : 'Disable Card payments?',
                ),
              ),
              _methodSwitch(
                'RavelGo Cash',
                'Paid from the rider\'s prepaid wallet balance.',
                s.walletPaymentEnabled,
                (v) => _apply(
                  () => AdminApi.updatePaymentSettings(walletPaymentEnabled: v),
                  confirmTitle: v ? 'Enable RavelGo Cash payments?' : 'Disable RavelGo Cash payments?',
                ),
              ),
            ],
          ),
        ),
        if (_saving) const Padding(padding: EdgeInsets.only(top: 16), child: Center(child: CircularProgressIndicator())),
      ],
    );
  }

  Widget _methodSwitch(String title, String subtitle, bool value, ValueChanged<bool> onChanged) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
      value: value,
      onChanged: _saving ? null : onChanged,
    );
  }
}
