import 'package:flutter/material.dart';
import 'package:ravelgo_user_app/Model/app_state.dart';
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
  bool isCashSelected = true;
  int selectedIndex = 0;

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
                      leading: Image.asset('assets/ic_cash.png'),
                      title: const Text('Cash'),
                      trailing: Checkbox(
                        activeColor: AppColors.primary,
                        value: isCashSelected,
                        onChanged: (bool? value) {
                          setState(() => isCashSelected = value!);
                        },
                      ),
                    ),
                    ListTile(
                      leading: Image.asset('assets/ic_transfer.png'),
                      title: const Text('Transfer'),
                      trailing: Checkbox(
                        activeColor: AppColors.primary,
                        value: !isCashSelected,
                        onChanged: (bool? value) {
                          setState(() => isCashSelected = !value!);
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
