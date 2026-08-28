import 'package:flutter/material.dart';
import 'package:ravelgo_user_app/theme/app_theme.dart';

class VoiceOverPage extends StatefulWidget {
  const VoiceOverPage({super.key});

  @override
  State<VoiceOverPage> createState() => _VoiceOverPageState();
}

class _VoiceOverPageState extends State<VoiceOverPage> {
  // LOCAL STATE ONLY: session-level audio preferences.
  final Map<String, String> _options = {
    'Voice volume': 'Normal',
    'Voice speed': 'Normal',
    'Language': 'English',
  };

  Future<void> _pickOption(String title, List<String> choices) async {
    final result = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            ),
            for (final c in choices)
              ListTile(
                title: Text(c),
                trailing: _options[title] == c
                    ? const Icon(Icons.check, color: AppColors.success)
                    : null,
                onTap: () => Navigator.pop(context, c),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (result != null) setState(() => _options[title] = result);
  }

  bool isVoiceOn = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [

            /// HEADER
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(Icons.arrow_back),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    "Voice Over",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),

            /// CONTENT
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [

                    /// TOGGLE CARD
                    _section(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 14),
                          child: Row(
                            children: [
                              const Expanded(
                                child: Text(
                                  "Voice over",
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),

                              /// SWITCH
                              Switch(
                                value: isVoiceOn,
                                onChanged: (value) {
                                  setState(() => isVoiceOn = value);
                                },
                                activeColor: AppColors.primary,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    /// DESCRIPTION
                    const Text(
                      "For a safer and more convenient ride experience, key details like new requests, pickup locations, and distances are read aloud. If your car has Bluetooth, the audio will automatically play through the speakers.",
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textPrimary,
                        height: 1.5,
                      ),
                    ),

                    const SizedBox(height: 20),

                    /// SETTINGS SECTION
                    if (isVoiceOn == true)
                    _section(
                      children: [
                        _tile("Voice volume", _options['Voice volume'],
                            () => _pickOption('Voice volume', const ['Quiet', 'Normal', 'Loud'])),
                        _divider(),
                        _tile("Voice speed", _options['Voice speed'],
                            () => _pickOption('Voice speed', const ['Slow', 'Normal', 'Fast'])),
                        _divider(),
                        _tile("Language", _options['Language'],
                            () => _pickOption('Language', const ['English', 'French', 'Yoruba', 'Hausa', 'Igbo'])),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// SECTION CONTAINER
  Widget _section({required List<Widget> children}) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(children: children),
    );
  }

  /// TILE
  Widget _tile(String title, String? value, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),

            if (value != null)
              Text(
                value,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                ),
              ),

            const SizedBox(width: 6),
            const Icon(Icons.keyboard_arrow_down, size: 18),
          ],
        ),
      ),
    );
  }

  /// DIVIDER
  Widget _divider() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Divider(
        height: 1,
        thickness: 1,
        color: AppColors.border,
      ),
    );
  }
}