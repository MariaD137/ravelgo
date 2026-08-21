import 'package:flutter/material.dart';
import 'package:ravelgo_driver_app/services/api_client.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';

class ContactUsScreen extends StatefulWidget {
  const ContactUsScreen({super.key});

  @override
  State<ContactUsScreen> createState() => _ContactUsScreenState();
}

class _ContactUsScreenState extends State<ContactUsScreen> {
  final _issueController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _issueController.dispose();
    super.dispose();
  }

  Future<void> _submitIssue() async {
    final issue = _issueController.text.trim();
    if (issue.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please describe your issue before submitting.')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      await ApiClient().post('/support-tickets', body: {
        'subject': 'Driver Support Request',
        'category': 'GENERAL',
        'description': issue,
      });

      if (!mounted) return;
      _issueController.clear();
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Your issue has been submitted. Our support team will respond shortly.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to submit. Please try again or email drivers@ravelgo.com.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Contact Support")),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            decoration: AppComponents.cardDecoration(),
            child: Column(
              children: [
                AppComponents.tile(title: "Call support", subtitle: "+234 700 RAVELGO", leading: Icons.call_outlined, onTap: () {}),
                AppComponents.divider(),
                AppComponents.tile(title: "Chat with us", subtitle: "In-app live chat", leading: Icons.chat_bubble_outline, onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Live chat coming soon')),
                  );
                }),
                AppComponents.divider(),
                AppComponents.tile(title: "Email us", subtitle: "drivers@ravelgo.com", leading: Icons.email_outlined, onTap: () {}),
                AppComponents.divider(),
                AppComponents.tile(title: "WhatsApp", subtitle: "Chat on WhatsApp", leading: Icons.chat_outlined, onTap: () {}),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Text("Report an issue", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          TextField(
            controller: _issueController,
            maxLines: 4,
            decoration: const InputDecoration(hintText: "Describe your issue...", border: OutlineInputBorder()),
          ),
          const SizedBox(height: 16),
          _isSubmitting
              ? const Center(child: CircularProgressIndicator())
              : AppComponents.primaryButton(text: "Submit", onPressed: _submitIssue),
        ],
      ),
    );
  }
}
