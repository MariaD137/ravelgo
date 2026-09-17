import 'package:flutter/material.dart';
import 'package:ravelgo_user_app/services/api_client.dart';
import 'package:ravelgo_user_app/services/auth_service.dart';
import 'package:ravelgo_user_app/services/rider_api.dart';
import 'package:ravelgo_user_app/theme/app_theme.dart';
import 'package:ravelgo_user_app/views/Login/login.dart';

class DeleteAccountScreen extends StatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  State<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends State<DeleteAccountScreen> {
  int? _selectedReasonIndex;
  bool _deleting = false;

  final List<String> _reasons = [
    "I am no longer using my account",
    "I want to change my phone number",
    "I don't understand how to use the service",
    "The service is not available in my city",
    "Other",
  ];

  /// Destructive action: always confirm first, then call the real backend
  /// deletion endpoint (DELETE /riders/me), sign out locally, and return to
  /// the login screen. The backend soft-deletes the account and disables the
  /// Cognito login so it can't be used again.
  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete your account?'),
        content: const Text(
            'This permanently removes your account and data. This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep account')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _deleting = true);
    try {
      await RiderApi.deleteMyAccount();
      await AuthService.signOut();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const Login()),
        (route) => false,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Your account has been deleted.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _deleting = false);
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text("Couldn't delete your account"),
          content: Text(e is ApiException
              ? '${e.message}\n\nYour account has NOT been deleted.'
              : 'Something went wrong and your account has NOT been deleted. Please try again or contact support.'),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
        ),
      );
    }
  }

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
                onPressed: (_selectedReasonIndex == null || _deleting) ? null : _confirmDelete,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  disabledBackgroundColor: AppColors.border,
                  disabledForegroundColor: AppColors.textMuted,
                ),
                child: Text(_deleting ? "Deleting…" : "Delete Account"),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}