import 'package:flutter/material.dart';
import 'package:ravelgo_driver_app/services/api/api_client.dart';
import 'package:ravelgo_driver_app/services/driver_session.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';

class DriverPreferencesScreen extends StatefulWidget {
  const DriverPreferencesScreen({super.key});

  @override
  State<DriverPreferencesScreen> createState() => _DriverPreferencesScreenState();
}

class _DriverPreferencesScreenState extends State<DriverPreferencesScreen> {
  late String _language = DriverSession.instance.profile!.preferredLanguage;
  late bool _quietMode = DriverSession.instance.profile!.quietModePreferred;
  bool _saving = false;
  String? _error;

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await DriverSession.instance.driverApi.updatePreferences(
        preferredLanguage: _language,
        quietModePreferred: _quietMode,
      );
      await DriverSession.instance.loadProfile();
      if (!mounted) return;
      Navigator.pop(context);
    } on ApiException catch (err) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = err.message;
      });
    }
  }

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
              ],
            ),
          ),
          const SizedBox(height: 16),
          // "Accept courier requests" / "Accept long-distance trips" have no
          // backend field yet (Driver has no such columns, and matching.ts
          // doesn't filter on anything like them) — shown disabled with an
          // honest note rather than a toggle that silently does nothing.
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: AppComponents.cardDecoration(),
            child: Column(
              children: [
                const SwitchListTile(
                  title: Text("Accept courier requests"),
                  subtitle: Text("Not available yet — courier requests are matched separately", style: TextStyle(fontSize: 12)),
                  value: true,
                  onChanged: null,
                ),
                AppComponents.divider(),
                const SwitchListTile(
                  title: Text("Accept long-distance trips"),
                  subtitle: Text("Not available yet", style: TextStyle(fontSize: 12)),
                  value: true,
                  onChanged: null,
                ),
              ],
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
          ],
          const SizedBox(height: 20),
          AppComponents.primaryButton(text: _saving ? "Saving…" : "Save preferences", onPressed: _saving ? null : _save),
        ],
      ),
    );
  }
}
