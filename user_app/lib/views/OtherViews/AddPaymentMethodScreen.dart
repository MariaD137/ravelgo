import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ravelgo_user_app/Model/app_state.dart';
import 'package:ravelgo_user_app/theme/app_theme.dart';

/// Add a card as a payment method.
///
/// LOCAL STATE ONLY - NOT PAYMENT PROCESSING: input is validated locally and
/// only masked display data (brand, last four, expiry) is kept in memory for
/// this session. No card is charged, stored remotely, or verified - the
/// payments backend (e.g. Stripe tokenization) is the integration point in
/// `_save`, and the UI says "saved for this session", never "verified".
class AddPaymentMethodScreen extends StatefulWidget {
  const AddPaymentMethodScreen({super.key});

  @override
  State<AddPaymentMethodScreen> createState() => _AddPaymentMethodScreenState();
}

class _AddPaymentMethodScreenState extends State<AddPaymentMethodScreen> {
  final _formKey = GlobalKey<FormState>();
  final _numberController = TextEditingController();
  final _expiryController = TextEditingController();
  final _cvvController = TextEditingController();

  @override
  void dispose() {
    _numberController.dispose();
    _expiryController.dispose();
    _cvvController.dispose();
    super.dispose();
  }

  String _brandFor(String digits) {
    if (digits.startsWith('4')) return 'VISA';
    if (digits.startsWith('5')) return 'Mastercard';
    if (digits.startsWith('506') || digits.startsWith('650')) return 'Verve';
    return 'Card';
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final digits = _numberController.text.replaceAll(RegExp(r'\D'), '');
    RiderAppState.instance.addPaymentMethod(SavedPaymentMethod(
      brand: _brandFor(digits),
      lastFour: digits.substring(digits.length - 4),
      expiry: _expiryController.text.trim(),
    ));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Card saved for this session (payment processing not connected yet)'),
    ));
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Add payment method')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Card number'),
              const SizedBox(height: 6),
              TextFormField(
                controller: _numberController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(19)],
                decoration: const InputDecoration(hintText: '0000 0000 0000 0000'),
                validator: (v) {
                  final digits = (v ?? '').replaceAll(RegExp(r'\D'), '');
                  return (digits.length < 13) ? 'Enter a valid card number' : null;
                },
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Expiry'),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _expiryController,
                          keyboardType: TextInputType.datetime,
                          decoration: const InputDecoration(hintText: 'MM/YY'),
                          validator: (v) =>
                              RegExp(r'^(0[1-9]|1[0-2])\/\d{2}$').hasMatch((v ?? '').trim())
                                  ? null
                                  : 'Use MM/YY',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('CVV'),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _cvvController,
                          keyboardType: TextInputType.number,
                          obscureText: true,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(4),
                          ],
                          decoration: const InputDecoration(hintText: '123'),
                          validator: (v) => ((v ?? '').length < 3) ? 'Invalid' : null,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.border),
                ),
                child: const Text(
                  'Payment processing is not connected in this build. Your card is kept on this '
                  'device for this session only and will not be charged or verified.',
                  style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                ),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _save,
                  child: const Padding(padding: EdgeInsets.symmetric(vertical: 14), child: Text('Save card')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
