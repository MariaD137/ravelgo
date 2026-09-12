import 'package:flutter/material.dart';
import 'package:ravelgo_driver_app/models/driver_profile.dart';
import 'package:ravelgo_driver_app/services/api_client.dart';
import 'package:ravelgo_driver_app/services/driver_api.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';

/// Real, persisted preferences (PATCH /api/drivers/me/preferences) plus a
/// contact phone number update (PATCH /api/drivers/me). This screen used to
/// hold everything in memory only — "Save preferences" just closed the
/// screen and reverted to the defaults next time it opened — and included
/// two toggles ("Accept courier requests", "Accept long-distance trips")
/// with no backing field anywhere in the backend, plus a claim that these
/// preferences feed "the Driver Matching Algorithm", which they do not:
/// matching (services/matching.ts) is not filtered by language or quiet
/// mode. Both are gone; what's shown here is exactly what's real.
class DriverPreferencesScreen extends StatefulWidget {
  final DriverProfile profile;
  const DriverPreferencesScreen({super.key, this.profile = const DriverProfile()});

  @override
  State<DriverPreferencesScreen> createState() => _DriverPreferencesScreenState();
}

class _DriverPreferencesScreenState extends State<DriverPreferencesScreen> {
  static const _languages = ["English", "French", "Yoruba", "Igbo", "Hausa"];

  late String _language = _languages.contains(widget.profile.preferredLanguage) ? widget.profile.preferredLanguage : _languages.first;
  late bool _quietMode = widget.profile.quietModePreferred;
  late final _phoneController = TextEditingController(text: widget.profile.phoneNumber);

  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final phone = _phoneController.text.trim();
      await Future.wait([
        DriverApi.updatePreferences(preferredLanguage: _language, quietModePreferred: _quietMode),
        if (phone.isNotEmpty && phone != widget.profile.phoneNumber) DriverApi.updatePhoneNumber(phone),
      ]);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Preferences saved.')));
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e is ApiException ? e.message : 'Could not save preferences.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Ride Preferences")),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (_error != null) ...[
            Text(_error!, style: const TextStyle(color: AppColors.danger)),
            const SizedBox(height: 12),
          ],
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
                    items: _languages.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                    onChanged: (v) => setState(() => _language = v ?? _language),
                  ),
                ),
                AppComponents.divider(),
                SwitchListTile(
                  title: const Text("Quiet mode"),
                  subtitle: const Text("Let riders know you prefer minimal conversation", style: TextStyle(fontSize: 12)),
                  value: _quietMode,
                  onChanged: (v) => setState(() => _quietMode = v),
                ),
                AppComponents.divider(),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: TextField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(labelText: "Phone number", border: InputBorder.none),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          AppComponents.primaryButton(text: _saving ? "Saving…" : "Save preferences", onPressed: _saving ? null : _save),
        ],
      ),
    );
  }
}
