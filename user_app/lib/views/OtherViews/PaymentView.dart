import 'package:flutter/material.dart';
import 'package:ravelgo_user_app/config/currency.dart';
import 'package:ravelgo_user_app/Model/app_state.dart';
import 'package:ravelgo_user_app/services/api_client.dart';
import 'package:ravelgo_user_app/services/wallet_api.dart';
import 'package:ravelgo_user_app/views/OtherViews/AddPaymentMethodScreen.dart';
import 'package:ravelgo_user_app/theme/app_theme.dart';

/// Payment settings: trip profile, active payment method, and saved cards.
/// LOCAL STATE ONLY: selections and saved cards live in RiderAppState for
/// this session; the payments backend is the integration point.
/// (Communication preferences and Work profile were removed from this screen -
/// they live under Account, where the same functionality already exists.)
class PaymentView extends StatefulWidget {
  @override
  _PaymentScreenState createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentView> {
  // Which of the two active RavelGo methods is selected. Cash was removed:
  // rides are paid by card or the RavelGo wallet.
  bool isCardSelected = true;
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

  Future<void> _addCard() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const AddPaymentMethodScreen()),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final cards = RiderAppState.instance.paymentMethods;
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
                    ListTile(
                      leading: const Icon(Icons.credit_card, color: AppColors.textSecondary),
                      title: const Text('Card'),
                      trailing: Checkbox(
                        activeColor: AppColors.primary,
                        value: isCardSelected,
                        onChanged: (bool? value) {
                          setState(() => isCardSelected = value!);
                        },
                      ),
                    ),
                    ListTile(
                      leading: const Icon(Icons.account_balance_wallet_outlined, color: AppColors.textSecondary),
                      title: const Text('RavelGo Wallet'),
                      trailing: Checkbox(
                        activeColor: AppColors.primary,
                        value: !isCardSelected,
                        onChanged: (bool? value) {
                          setState(() => isCardSelected = !value!);
                        },
                      ),
                    ),
                    if (cards.isNotEmpty) ...[
                      const Divider(),
                      for (final card in cards)
                        ListTile(
                          leading: const Icon(Icons.credit_card, color: AppColors.textSecondary),
                          title: Text('${card.brand} •••• ${card.lastFour}'),
                          subtitle: Text('Expires ${card.expiry}',
                              style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                        ),
                    ],
                    const SizedBox(height: 4),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _addCard,
                        icon: const Icon(Icons.add),
                        label: const Text('Add payment method'),
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
