import 'package:flutter/material.dart';
import 'package:ravelgo_user_app/theme/app_theme.dart';

class DeleteAccountScreen extends StatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  State<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends State<DeleteAccountScreen> {
  int? _selectedReasonIndex;

  final List<String> _reasons = [
    "I am no longer using my account",
    "I want to change my hone number",
    "I don't understand how to use the service",
    "The service is not available in my city",
    "Other",
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        leading: const BackButton(color: AppColors.textPrimary),
        backgroundColor: AppColors.surface,
        elevation: 0,
        centerTitle: true,
        title: const Text("Delete Account", style: TextStyle(color: AppColors.textPrimary)),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          children: [
            const SizedBox(height: 10),
            const Text(
              "We're really sorry to see you go. Are you sure you want to delete your account? Once you confirm, your data will be gone.",
              style: TextStyle(fontSize: 15, height: 1.5),
            ),
            const SizedBox(height: 30),
            Expanded(
              child: ListView.separated(
                itemCount: _reasons.length,
                separatorBuilder: (_, __) => const Divider(),
                itemBuilder: (context, index) {
                  return CheckboxListTile(
                    value: _selectedReasonIndex == index,
                    onChanged: (_) {
                      setState(() => _selectedReasonIndex = index);
                    },
                    title: Text(_reasons[index]),
                    activeColor: AppColors.primary,
                    controlAffinity: ListTileControlAffinity.leading,
                    checkboxShape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _selectedReasonIndex == null
                    ? null
                    : () {
                  // Handle account deletion logic
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.textPrimary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  disabledBackgroundColor: AppColors.border,
                  disabledForegroundColor: AppColors.textMuted,
                ),
                child: const Text("Delete Account"),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}