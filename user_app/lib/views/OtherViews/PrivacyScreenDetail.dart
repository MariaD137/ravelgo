import 'package:flutter/material.dart';

class PrivacyScreenDetail extends StatelessWidget {
  const PrivacyScreenDetail({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        leading: const BackButton(color: Colors.black),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: const Text("Privacy", style: TextStyle(color: Colors.black)),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 0,
          child: ListTile(
            leading: const Icon(Icons.copy_outlined),
            title: const Text("Personal data", style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: const Text("Download a copy of your data"),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () {
              // Navigate or trigger data download
            },
          ),
        ),
      ),
    );
  }
}