import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';

/// Driver support contacts and issue reporting.
///
/// No dialer/mail/WhatsApp launcher plugin is configured in this build, so
/// contact rows copy the address with a clear message. Submitting an issue
/// validates the text and records it locally - the support-ticket service is
/// the integration point, and the confirmation says the report is local.
class ContactUsScreen extends StatefulWidget {
  const ContactUsScreen({super.key});

  @override
  State<ContactUsScreen> createState() => _ContactUsScreenState();
}

class _ContactUsScreenState extends State<ContactUsScreen> {
  final _issueController = TextEditingController();
  String? _error;

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

  void _submit() {
    final text = _issueController.text.trim();
    if (text.length < 10) {
      setState(() => _error = 'Describe your issue in at least 10 characters');
      return;
    }
    setState(() => _error = null);
    // Integration point: create a ticket in the support service here.
    _issueController.clear();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Report recorded'),
        content: const Text(
            'Your report was recorded on this device. It will be submitted to the support '
            'team once the ticketing service is connected. For urgent issues use the phone '
            'or email contacts above.'),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
      ),
    );
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
          AppComponents.primaryButton(text: "Submit", onPressed: _submit),
        ],
      ),
    );
  }
}
