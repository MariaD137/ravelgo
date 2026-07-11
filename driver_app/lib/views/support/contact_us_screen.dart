import 'package:flutter/material.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';

class ContactUsScreen extends StatelessWidget {
  const ContactUsScreen({super.key});

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
                AppComponents.tile(title: "Chat with us", subtitle: "In-app live chat", leading: Icons.chat_bubble_outline, onTap: () {}),
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
          const TextField(
            maxLines: 4,
            decoration: InputDecoration(hintText: "Describe your issue...", border: OutlineInputBorder()),
          ),
          const SizedBox(height: 16),
          AppComponents.primaryButton(text: "Submit", onPressed: () {}),
        ],
      ),
    );
  }
}
