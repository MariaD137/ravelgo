import 'package:flutter/material.dart';
import 'package:ravelgo_rider_app/views/AccountView/VoiceOverPage.dart';

class AppSettingsPage extends StatelessWidget {
  const AppSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F6F6),
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
                    "App settings",
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
                  children: [

                    /// SECTION 1
                    _sectionContainer(
                      children: [
                        _settingsTile(
                          title: "Voice over",
                          value: "Off",
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (context) => VoiceOverPage()),
                            );
                          },
                        ),
                        _divider(),
                        _settingsTile(
                          title: "Sound and voice",
                          onTap: () {},
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    /// SECTION 2
                    _sectionContainer(
                      children: [
                        _settingsTile(
                          title: "Language",
                          value: "English",
                          onTap: () {},
                        ),
                        // _divider(),
                        // _settingsTile(
                        //   title: "Theme",
                        //   value: "Off",
                        //   onTap: () {},
                        // ),
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
  Widget _sectionContainer({required List<Widget> children}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(children: children),
    );
  }

  /// TILE
  Widget _settingsTile({
    required String title,
    String? value,
    required VoidCallback onTap,
  }) {
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
                  fontSize: 14,
                  color: Colors.black54,
                ),
              ),

            const SizedBox(width: 6),

            const Icon(Icons.chevron_right, size: 18),
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