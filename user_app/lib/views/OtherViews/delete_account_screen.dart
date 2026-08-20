import 'package:flutter/material.dart';
import 'package:ravelgo_user/services/auth_service.dart';
import 'package:ravelgo_user/views/Login/login.dart';

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
      backgroundColor: Colors.white,
      appBar: AppBar(
        leading: const BackButton(color: Colors.black),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: const Text("Delete Account", style: TextStyle(color: Colors.black)),
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
                separatorBuilder: (_, _) => const Divider(),
                itemBuilder: (context, index) {
                  return CheckboxListTile(
                    value: _selectedReasonIndex == index,
                    onChanged: (_) {
                      setState(() => _selectedReasonIndex = index);
                    },
                    title: Text(_reasons[index]),
                    activeColor: Colors.yellow[700],
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
                    : () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Delete Account'),
                      content: const Text(
                        'Are you sure you want to delete your account? This action cannot be undone.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancel'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Delete', style: TextStyle(color: Colors.red)),
                        ),
                      ],
                    ),
                  );
                  if (confirmed == true) {
                    await AuthService().signOut();
                    if (!context.mounted) return;
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(builder: (_) => Login()),
                      (Route<dynamic> route) => false,
                    );
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.yellow[700],
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  disabledBackgroundColor: Colors.grey[300],
                  disabledForegroundColor: Colors.black38,
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