import 'package:flutter/material.dart';
import 'package:ravelgo_admin/theme/app_theme.dart';
import 'package:ravelgo_admin/views/shell/admin_shell.dart';

class AdminLoginScreen extends StatelessWidget {
  const AdminLoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 40),
                const Text("RavelGo Admin", style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                const Text("Sign in to manage drivers, riders, trips and operations", style: TextStyle(fontSize: 14, color: Colors.black54)),
                const SizedBox(height: 32),
                const TextField(decoration: InputDecoration(labelText: "Work email", border: OutlineInputBorder())),
                const SizedBox(height: 16),
                const TextField(
                  obscureText: true,
                  decoration: InputDecoration(labelText: "Password", border: OutlineInputBorder(), suffixIcon: Icon(Icons.visibility_off)),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(onPressed: () {}, child: Text("Forgot Password?", style: TextStyle(color: Colors.yellow[700]))),
                ),
                const SizedBox(height: 20),
                AppComponents.primaryButton(
                  text: "Sign in",
                  onPressed: () {
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(builder: (context) => const AdminShell()),
                      (route) => false,
                    );
                  },
                ),
                const SizedBox(height: 16),
                const Center(
                  child: Text("Access is restricted to authorized RavelGo staff.", style: TextStyle(fontSize: 12, color: Colors.black45)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
