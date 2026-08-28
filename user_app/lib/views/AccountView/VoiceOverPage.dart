import 'package:flutter/material.dart';
import 'package:ravelgo_user_app/theme/app_theme.dart';

class VoiceOverPage extends StatefulWidget {
  const VoiceOverPage({super.key});

  @override
  State<VoiceOverPage> createState() => _VoiceOverPageState();
}

class _VoiceOverPageState extends State<VoiceOverPage> {
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
                        color: Colors.black87,
                        height: 1.5,
                      ),
                    ),

                    const SizedBox(height: 20),

                    /// SETTINGS SECTION
                    if (isVoiceOn == true)
                    _section(
                      children: [
                        _tile("Voice volume", "Normal"),
                        _divider(),
                        _tile("Voice speed", null),
                        _divider(),
                        _tile("Language", "English"),
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(children: children),
    );
  }

  /// TILE
  Widget _tile(String title, String? value) {
    return InkWell(
      onTap: () {},
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
                  color: Colors.black54,
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
        color: Colors.grey.shade300,
      ),
    );
  }
}