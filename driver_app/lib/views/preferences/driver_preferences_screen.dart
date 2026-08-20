import 'package:flutter/material.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';

class DriverPreferencesScreen extends StatefulWidget {
  const DriverPreferencesScreen({super.key});

  @override
  State<DriverPreferencesScreen> createState() => _DriverPreferencesScreenState();
}

class _DriverPreferencesScreenState extends State<DriverPreferencesScreen> {
  String _language = "English";
  bool _quietMode = false;
  bool _acceptCourier = false;
  bool _acceptLongTrips = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Ride Preferences")),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            "These preferences power the Driver Matching Algorithm to pair you with riders that fit your style.",
            style: TextStyle(fontSize: 14, color: Colors.black54),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: AppComponents.cardDecoration(),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: DropdownButtonFormField<String>(
                    initialValue: _language,
                    decoration: const InputDecoration(labelText: "Preferred language", border: InputBorder.none),
                    items: const ["English", "French", "Yoruba", "Igbo", "Hausa"]
                        .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                        .toList(),
                    onChanged: (v) => setState(() => _language = v ?? _language),
                  ),
                ),
                AppComponents.divider(),
                SwitchListTile(
                  title: const Text("Quiet mode"),
                  subtitle: const Text("Minimal conversation during rides", style: TextStyle(fontSize: 12)),
                  value: _quietMode,
                  onChanged: (v) => setState(() => _quietMode = v),
                ),
                AppComponents.divider(),
                SwitchListTile(
                  title: const Text("Accept courier requests"),
                  subtitle: const Text("Note: courier pickups are handled via the Riders app", style: TextStyle(fontSize: 12)),
                  value: _acceptCourier,
                  onChanged: (v) => setState(() => _acceptCourier = v),
                ),
                AppComponents.divider(),
                SwitchListTile(
                  title: const Text("Accept long-distance trips"),
                  value: _acceptLongTrips,
                  onChanged: (v) => setState(() => _acceptLongTrips = v),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          AppComponents.primaryButton(text: "Save preferences", onPressed: () => Navigator.pop(context)),
        ],
      ),
    );
  }
}
