import 'package:flutter/material.dart';
import 'package:ravelgo_user/components/basic_components.dart';

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
  void dispose() {
    accountNameController.dispose();
    accountNumberController.dispose();
    bankNameController.dispose();
    currencyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFFFFF),
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
                      onPressed: isValid ? () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Bank account saved successfully')),
                        );
                        Navigator.pop(context);
                      } : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFFD500),
                        foregroundColor: Colors.black,
                        disabledBackgroundColor:
                        const Color(0xFFFFD500).withValues(alpha: 0.4),
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
                            color: Colors.grey.shade400),
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
        fillColor: Colors.white,
        contentPadding:
        const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide:
          BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide:
          BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide:
          const BorderSide(color: Colors.black),
        ),
      ),
    );
  }

  /// DROPDOWN FIELD (UI STYLE)
  Widget _dropdown(
      TextEditingController controller, String hint) {
    return InkWell(
      onTap: () {
        /// TODO: open currency selector
      },
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.shade300),
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
                      ? Colors.grey
                      : Colors.black,
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