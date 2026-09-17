import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ravelgo_driver_app/services/api_client.dart';
import 'package:ravelgo_driver_app/services/support_api.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';

/// Driver support contacts and issue reporting.
///
/// No dialer/mail/WhatsApp launcher plugin is configured in this build, so
/// contact rows copy the address with a clear message. Submitting an issue
/// creates a real support ticket via the backend (POST /support-tickets, the
/// same endpoint the Support screen uses), so a driver's report reaches the
/// support team instead of being dropped.
class ContactUsScreen extends StatefulWidget {
  const ContactUsScreen({super.key});

  @override
  State<ContactUsScreen> createState() => _ContactUsScreenState();
}

class _ContactUsScreenState extends State<ContactUsScreen> {
  final _issueController = TextEditingController();
  String? _error;
  bool _submitting = false;

  @override
  void dispose() {
    _issueController.dispose();
    super.dispose();
  }

  void _copy(String label, String value) {
    Clipboard.setData(ClipboardData(text: value));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label copied: $value')),
    );
  }

  void _chatUnavailable() {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Live chat requires the support service - not available in this build'),
    ));
  }

  Future<void> _submit() async {
    final text = _issueController.text.trim();
    if (text.length < 10) {
      setState(() => _error = 'Describe your issue in at least 10 characters');
      return;
    }
    setState(() {
      _error = null;
      _submitting = true;
    });
    try {
      // The SupportTicket model has no separate body field (subject +
      // category only — see backend schema), so the driver's description is
      // the subject. Same endpoint the Support screen uses.
      await SupportApi.createTicket(subject: text, category: 'Driver-reported issue');
      if (!mounted) return;
      _issueController.clear();
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Report submitted'),
          content: const Text(
              'Your report has been sent to our support team. You can track it under '
              'Support. For urgent issues use the phone or email contacts above.'),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e is ApiException ? e.message : 'Could not submit your report. Please try again.');
    } finally {
      if (mounted) setState(() => _submitting = false);
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
                AppComponents.tile(
                    title: "Call support",
                    subtitle: "+234 700 RAVELGO (tap to copy)",
                    leading: Icons.call_outlined,
                    onTap: () => _copy('Support number', '+234700RAVELGO')),
                AppComponents.divider(),
                AppComponents.tile(
                    title: "Chat with us",
                    subtitle: "In-app live chat",
                    leading: Icons.chat_bubble_outline,
                    onTap: _chatUnavailable),
                AppComponents.divider(),
                AppComponents.tile(
                    title: "Email us",
                    subtitle: "drivers@ravelgo.com (tap to copy)",
                    leading: Icons.email_outlined,
                    onTap: () => _copy('Support email', 'drivers@ravelgo.com')),
                AppComponents.divider(),
                AppComponents.tile(
                    title: "WhatsApp",
                    subtitle: "+234 700 728 3546 (tap to copy)",
                    leading: Icons.chat_outlined,
                    onTap: () => _copy('WhatsApp number', '+2347007283546')),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Text("Report an issue", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          TextField(
            controller: _issueController,
            maxLines: 4,
            decoration: InputDecoration(
              hintText: "Describe your issue...",
              border: const OutlineInputBorder(),
              errorText: _error,
            ),
          ),
          const SizedBox(height: 16),
          AppComponents.primaryButton(
              text: _submitting ? "Submitting…" : "Submit",
              onPressed: _submitting ? null : _submit),
        ],
      ),
    );
  }
}
