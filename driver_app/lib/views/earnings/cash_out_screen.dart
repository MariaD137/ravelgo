import 'package:flutter/material.dart';
import 'package:ravelgo_driver_app/services/api_client.dart';
import 'package:ravelgo_driver_app/services/driver_api.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';

/// Manage the payout bank account (POST/GET /api/payouts/bank-account).
///
/// The actual transfer of funds is initiated by the RavelGo team through the
/// payments provider — a driver can't move money themselves — so this screen
/// sets up where payouts are sent, and says so honestly.
class CashOutScreen extends StatefulWidget {
  const CashOutScreen({super.key});

  @override
  State<CashOutScreen> createState() => _CashOutScreenState();
}

class _CashOutScreenState extends State<CashOutScreen> {
  final _holderController = TextEditingController();
  final _bankController = TextEditingController();
  final _accountController = TextEditingController();
  final _routingController = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  String? _loadError;
  String? _formError;
  String? _existingSummary;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _holderController.dispose();
    _bankController.dispose();
    _accountController.dispose();
    _routingController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final acct = await DriverApi.bankAccount();
      if (!mounted) return;
      setState(() {
        if (acct != null) {
          _holderController.text = '${acct['accountHolderName'] ?? ''}';
          _bankController.text = '${acct['bankName'] ?? ''}';
          final num = '${acct['accountNumber'] ?? ''}';
          final last4 = num.length >= 4 ? num.substring(num.length - 4) : num;
          _existingSummary = num.isEmpty ? null : '${acct['bankName'] ?? 'Bank'} ••••$last4';
        }
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e is ApiException && e.statusCode == 403
            ? 'Your account isn\'t set up as a driver yet.'
            : e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    final holder = _holderController.text.trim();
    final bank = _bankController.text.trim();
    final account = _accountController.text.trim();
    final routing = _routingController.text.trim();
    if (holder.isEmpty || bank.isEmpty) {
      setState(() => _formError = 'Enter the account holder and bank name');
      return;
    }
    if (account.length < 8) {
      setState(() => _formError = 'Account number must be at least 8 digits');
      return;
    }
    if (routing.length < 9) {
      setState(() => _formError = 'Routing number must be at least 9 digits');
      return;
    }
    setState(() {
      _formError = null;
      _saving = true;
    });
    try {
      await DriverApi.saveBankAccount(
        accountHolderName: holder,
        bankName: bank,
        accountNumber: account,
        routingNumber: routing,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Payout account saved.')));
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _formError = e is ApiException ? e.message : e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Payout account')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (_loadError != null ? _err() : _form()),
    );
  }

  Widget _err() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_loadError!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.danger)),
            TextButton(onPressed: _load, child: const Text('Try again')),
          ]),
        ),
      );

  Widget _form() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: AppColors.surfaceElevated, borderRadius: BorderRadius.circular(12)),
            child: Text(
              _existingSummary == null
                  ? 'Add the bank account where your earnings should be paid. The RavelGo team sends payouts to this account.'
                  : 'Payouts go to $_existingSummary. Update the details below if needed.',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
          ),
          const SizedBox(height: 20),
          _field('Account holder name', _holderController),
          const SizedBox(height: 16),
          _field('Bank name', _bankController),
          const SizedBox(height: 16),
          _field('Account number', _accountController, number: true),
          const SizedBox(height: 16),
          _field('Routing / sort code', _routingController, number: true),
          if (_formError != null) ...[
            const SizedBox(height: 12),
            Text(_formError!, style: const TextStyle(color: AppColors.danger)),
          ],
          const SizedBox(height: 24),
          AppComponents.primaryButton(
            text: _saving ? 'Saving…' : 'Save payout account',
            onPressed: _saving ? null : _save,
          ),
        ],
      ),
    );
  }

  Widget _field(String label, TextEditingController controller, {bool number = false}) {
    return TextField(
      controller: controller,
      keyboardType: number ? TextInputType.number : TextInputType.text,
      decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
    );
  }
}
