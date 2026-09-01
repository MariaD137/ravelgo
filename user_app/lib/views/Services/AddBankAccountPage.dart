import 'package:flutter/material.dart';
import 'package:ravelgo_user_app/components/basic_components.dart';
import 'package:ravelgo_user_app/theme/app_theme.dart';

class AddBankAccountPage extends StatefulWidget {
  const AddBankAccountPage({super.key});

  @override
  State<AddBankAccountPage> createState() => _AddBankAccountPageState();
}

class _AddBankAccountPageState extends State<AddBankAccountPage> {

  final accountNameController = TextEditingController();
  final accountNumberController = TextEditingController();
  final bankNameController = TextEditingController();
  final currencyController = TextEditingController();

  bool get isValid =>
      accountNameController.text.isNotEmpty &&
          accountNumberController.text.isNotEmpty &&
          bankNameController.text.isNotEmpty &&
          currencyController.text.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            /// HEADER
            AppComponents.header(context, "Add a bank account"),

            /// FORM
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [

                    _label("Account Name"),
                    _input(accountNameController,
                        "Enter your account name"),

                    const SizedBox(height: 16),

                    _label("Account Number"),
                    _input(accountNumberController,
                        "Enter your account number"),

                    const SizedBox(height: 16),

                    _label("Bank Name"),
                    _input(bankNameController,
                        "Enter your bank name"),

                    const SizedBox(height: 16),

                    _label("Currency"),
                    _dropdown(currencyController, "Enter Currency"),

                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),

            /// BUTTONS
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [

                  /// SAVE BUTTON
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: isValid ? () {} : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: AppColors.textPrimary,
                        disabledBackgroundColor:
                        AppColors.primary.withOpacity(0.4),
                        padding:
                        const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        "Save",
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 10),

                  /// CANCEL BUTTON
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        padding:
                        const EdgeInsets.symmetric(vertical: 14),
                        side: BorderSide(
                            color: AppColors.border),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text(
                        "Cancel",
                        style: TextStyle(fontSize: 15),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// LABEL
  Widget _label(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: const TextStyle(
          fontWeight: FontWeight.w500,
          fontSize: 14,
        ),
      ),
    );
  }

  /// INPUT FIELD
  Widget _input(TextEditingController controller, String hint) {
    return TextField(
      controller: controller,
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: AppColors.surface,
        contentPadding:
        const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide:
          BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide:
          BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide:
          const BorderSide(color: AppColors.textPrimary),
        ),
      ),
    );
  }

  /// DROPDOWN FIELD (UI STYLE)
  Widget _dropdown(
      TextEditingController controller, String hint) {
    return InkWell(
      onTap: () async {
        final result = await showModalBottomSheet<String>(
          context: context,
          builder: (context) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(hint,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                ),
                for (final c in const ['NGN - Nigerian Naira', 'USD - US Dollar', 'GBP - British Pound', 'EUR - Euro'])
                  ListTile(
                    title: Text(c),
                    trailing: controller.text == c
                        ? const Icon(Icons.check, color: AppColors.success)
                        : null,
                    onTap: () => Navigator.pop(context, c),
                  ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
        if (result != null) {
          setState(() => controller.text = result);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                controller.text.isEmpty
                    ? hint
                    : controller.text,
                style: TextStyle(
                  color: controller.text.isEmpty
                      ? AppColors.textMuted
                      : AppColors.textPrimary,
                ),
              ),
            ),
            const Icon(Icons.keyboard_arrow_down),
          ],
        ),
      ),
    );
  }
}