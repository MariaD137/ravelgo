import 'package:flutter/material.dart';
import 'package:ravelgo_driver_app/services/api_client.dart';
import 'package:ravelgo_driver_app/services/driver_api.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';

/// Manage the payout bank account (POST/GET /api/payouts/bank-account).
///
/// The actual transfer of funds is initiated by the RavelGo team through the
/// payments provider — a driver can't move money themselves — so this screen
/// sets up where payouts are sent, and says so honestly.
///
/// The bank is chosen from GET /api/payouts/banks (Paystack's own bank list)
/// rather than typed freehand: the selection's bank CODE is what an
/// automated Paystack transfer actually keys off
/// (backend/src/services/payouts.ts#processPayout) — a free-text bank name
/// can never trigger one, silently falling back to the manual-payout path.
class CashOutScreen extends StatefulWidget {
  const CashOutScreen({super.key});

  @override
  State<CashOutScreen> createState() => _CashOutScreenState();
}

class _CashOutScreenState extends State<CashOutScreen> {
  final _holderController = TextEditingController();
  final _accountController = TextEditingController();

  bool _loading = true;
  bool _banksLoading = true;
  bool _saving = false;
  String? _loadError;
  String? _banksError;
  String? _formError;
  String? _existingSummary;
  bool _existingHasBankCode = false;

  List<PayoutBank> _banks = const [];
  PayoutBank? _selectedBank;

  @override
  void initState() {
    super.initState();
    _load();
    _loadBanks();
  }

  @override
  void dispose() {
    _holderController.dispose();
    _accountController.dispose();
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
          final num = '${acct['accountNumber'] ?? ''}';
          final last4 = num.length >= 4 ? num.substring(num.length - 4) : num;
          _existingSummary = num.isEmpty ? null : '${acct['bankName'] ?? 'Bank'} ••••$last4';
          final code = acct['bankCode'] as String?;
          _existingHasBankCode = code != null && code.isNotEmpty;
          if (code != null && code.isNotEmpty) {
            _selectedBank = PayoutBank(name: '${acct['bankName'] ?? ''}', code: code);
          }
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

  Future<void> _loadBanks() async {
    setState(() {
      _banksLoading = true;
      _banksError = null;
    });
    try {
      final banks = await DriverApi.listBanks();
      if (!mounted) return;
      setState(() {
        _banks = banks;
        _banksLoading = false;
        // Re-resolve the saved selection against the full list once it's in
        // (its name may differ in casing/spacing from what's stored), so the
        // dropdown shows an exact match instead of a synthesized entry.
        if (_selectedBank != null) {
          for (final b in banks) {
            if (b.code == _selectedBank!.code) {
              _selectedBank = b;
              break;
            }
          }
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _banksError = e is ApiException ? e.message : 'Could not load the bank list.';
        _banksLoading = false;
      });
    }
  }

  Future<void> _save() async {
    final holder = _holderController.text.trim();
    final account = _accountController.text.trim();
    final bank = _selectedBank;
    if (holder.isEmpty) {
      setState(() => _formError = 'Enter the account holder name');
      return;
    }
    if (bank == null) {
      setState(() => _formError = 'Choose your bank');
      return;
    }
    if (account.length < 8) {
      setState(() => _formError = 'Account number must be at least 8 digits');
      return;
    }
    setState(() {
      _formError = null;
      _saving = true;
    });
    try {
      await DriverApi.saveBankAccount(
        accountHolderName: holder,
        bankName: bank.name,
        bankCode: bank.code,
        accountNumber: account,
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
          if (_existingSummary != null && !_existingHasBankCode) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppColors.warning.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
              child: const Text(
                'This account was saved without a bank selection, so payouts to it are sent manually rather than automatically. Choose your bank below and save to switch to automatic payouts.',
                style: TextStyle(color: AppColors.warning, fontSize: 12),
              ),
            ),
          ],
          const SizedBox(height: 20),
          _field('Account holder name', _holderController),
          const SizedBox(height: 16),
          _bankPicker(),
          const SizedBox(height: 16),
          _field('Account number', _accountController, number: true),
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

  Widget _bankPicker() {
    if (_banksLoading) {
      return const SizedBox(
        height: 56,
        child: Center(child: SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))),
      );
    }
    if (_banksError != null) {
      return Row(
        children: [
          Expanded(child: Text(_banksError!, style: const TextStyle(color: AppColors.danger, fontSize: 13))),
          TextButton(onPressed: _loadBanks, child: const Text('Retry')),
        ],
      );
    }
    return DropdownButtonFormField<PayoutBank>(
      // A PayoutBank equal to _selectedBank by code (not identity) may not
      // be the exact same instance in _banks after a re-resolve, so match by
      // code rather than relying on DropdownButtonFormField's == check.
      initialValue: _selectedBank == null
          ? null
          : _banks.where((b) => b.code == _selectedBank!.code).cast<PayoutBank?>().firstOrNull,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Bank', border: OutlineInputBorder()),
      items: _banks
          .map((b) => DropdownMenuItem<PayoutBank>(value: b, child: Text(b.name, overflow: TextOverflow.ellipsis)))
          .toList(),
      onChanged: (b) => setState(() => _selectedBank = b),
      hint: const Text('Choose your bank'),
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
