import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:ravelgo_user_app/config/currency.dart';
import 'package:ravelgo_user_app/services/api_client.dart';
import 'package:ravelgo_user_app/services/stripe_service.dart';
import 'package:ravelgo_user_app/services/wallet_api.dart';
import 'package:ravelgo_user_app/theme/app_theme.dart';

/// Payment settings: trip profile and the RavelGo Cash wallet.
/// (Communication preferences and Work profile were removed from this screen -
/// they live under Account, where the same functionality already exists.)
class PaymentView extends StatefulWidget {
  @override
  _PaymentScreenState createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentView> {
  int selectedIndex = 0;

  // Live wallet, loaded from the backend (GET /api/wallet/me + /transactions).
  WalletBalance? _wallet;
  List<WalletTransaction> _txns = const [];
  bool _walletLoading = true;
  String? _walletError;

  @override
  void initState() {
    super.initState();
    _loadWallet();
  }

  Future<void> _loadWallet() async {
    setState(() {
      _walletLoading = true;
      _walletError = null;
    });
    try {
      final results = await Future.wait([WalletApi.me(), WalletApi.transactions()]);
      if (!mounted) return;
      setState(() {
        _wallet = results[0] as WalletBalance;
        _txns = results[1] as List<WalletTransaction>;
        _walletLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _walletError = e is ApiException && e.statusCode == 403
            ? 'Sign in as a rider to see your wallet.'
            : e.toString();
        _walletLoading = false;
      });
    }
  }

  bool _toppingUp = false;

  /// Add funds to the RavelGo wallet: the backend starts a real Stripe
  /// PaymentIntent, and the rider confirms it in the PaymentSheet. The balance
  /// is credited by the signed webhook once Stripe settles, so we reload after
  /// (it may take a moment) rather than assuming the money landed.
  Future<void> _topUp() async {
    if (!StripeService.isConfigured) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Card payments are not configured yet.')),
      );
      return;
    }
    final amount = await _askAmount();
    if (amount == null) return;
    setState(() => _toppingUp = true);
    try {
      final clientSecret = await WalletApi.startTopUp(amount);
      await StripeService.presentPaymentSheet(clientSecret: clientSecret);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Payment received. Your balance will update shortly.')),
      );
      await _loadWallet();
    } on StripeException catch (_) {
      // Rider cancelled or the sheet failed — nothing was charged.
    } catch (e) {
      if (!mounted) return;
      final msg = e is ApiException ? e.message : e.toString();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      if (mounted) setState(() => _toppingUp = false);
    }
  }

  Future<double?> _askAmount() async {
    final ctrl = TextEditingController();
    return showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add funds'),
        content: TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(prefixText: '${Currency.symbol} ', hintText: 'Amount', border: const OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              final v = double.tryParse(ctrl.text.trim());
              if (v == null || v <= 0) {
                Navigator.pop(context);
              } else {
                Navigator.pop(context, v);
              }
            },
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(70),
        child: Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.only(
              bottomLeft: Radius.circular(24),
              bottomRight: Radius.circular(24),
            ),
            boxShadow: [
              BoxShadow(color: AppColors.border, blurRadius: 4, offset: Offset(0, 2)),
            ],
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: const [
                  BackButton(color: AppColors.textPrimary),
                  Spacer(),
                  Text('Payment',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.normal, color: AppColors.textPrimary)),
                  Spacer(),
                  SizedBox(width: 64)
                ],
              ),
            ),
          ),
        ),
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 12),
            _walletCard(),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(25),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Trip profile', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.surfaceElevated,
                        borderRadius: BorderRadius.circular(25),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        children: [
                          _buildOption('Personal', 0, isSelected: selectedIndex == 0),
                          _buildOption('Work', 1, isSelected: selectedIndex == 1),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(25),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Payment methods', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    const ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.credit_card, color: AppColors.textSecondary),
                      title: Text('Card'),
                      subtitle: Text('Entered securely at checkout via Stripe, each time.'),
                    ),
                    const ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.account_balance_wallet_outlined, color: AppColors.textSecondary),
                      title: Text('RavelGo Cash'),
                      subtitle: Text('Your prepaid balance above.'),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: AppColors.surfaceElevated, borderRadius: BorderRadius.circular(10)),
                      child: const Text(
                        'Saved cards aren\'t supported yet — you\'ll enter your card details at checkout for each '
                        'ride, rental or booking. Nothing is stored on this device or by RavelGo.',
                        style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _walletCard() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 0),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, AppColors.primaryDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.account_balance_wallet, color: Colors.white),
              const SizedBox(width: 8),
              const Text('RavelGo Wallet',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh, color: Colors.white, size: 20),
                onPressed: _walletLoading ? null : _loadWallet,
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_walletLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: SizedBox(
                  height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
            )
          else if (_walletError != null)
            Text(_walletError!, style: const TextStyle(color: Colors.white))
          else
            Text(
              Currency.format(_wallet!.balance),
              style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.bold),
            ),
          if (!_walletLoading && _walletError == null) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _toppingUp ? null : _topUp,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: AppColors.primaryDark,
                ),
                icon: _toppingUp
                    ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.add),
                label: Text(_toppingUp ? 'Starting…' : 'Add funds'),
              ),
            ),
            const Divider(color: Colors.white24, height: 28),
            const Text('Recent activity', style: TextStyle(color: Colors.white70, fontSize: 13)),
            const SizedBox(height: 6),
            if (_txns.isEmpty)
              const Text('No transactions yet.', style: TextStyle(color: Colors.white70, fontSize: 13))
            else
              ..._txns.take(5).map((t) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text('${_prettyTxn(t.type)} · ${t.status.toLowerCase()}',
                              style: const TextStyle(color: Colors.white, fontSize: 13)),
                        ),
                        Text(Currency.format(t.amount),
                            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  )),
          ],
        ],
      ),
    );
  }

  String _prettyTxn(String s) =>
      s.isEmpty ? '' : s[0] + s.substring(1).toLowerCase().replaceAll('_', ' ');

  Expanded _buildOption(String label, int index, {required bool isSelected}) {
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            selectedIndex = index;
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(25),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : AppColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
