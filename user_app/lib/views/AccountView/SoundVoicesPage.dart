import 'package:flutter/material.dart';
import 'package:ravelgo_user_app/theme/app_theme.dart';

class SoundVoicesPage extends StatefulWidget {
  const SoundVoicesPage({super.key});

  @override
  State<SoundVoicesPage> createState() => _SoundVoicesPageState();
}

class _SoundVoicesPageState extends State<SoundVoicesPage> {
  // LOCAL STATE ONLY: the currently selected notification sound.
  String _selected = 'Bells';

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
                    "Sound an voices",
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

                    /// TITLE
                    const Padding(
                      padding: EdgeInsets.only(bottom: 10),
                      child: Text(
                        "Incoming Request Sound",
                        style: TextStyle(
                          fontSize: 14,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),

                    /// LIST CARD
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          _soundTile("Bells"),
                          _divider(),
                          _soundTile("Kalimba"),
                          _divider(),
                          _soundTile("Kalimba"),
                        ],
                      ),
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

  /// SOUND TILE
  Widget _soundTile(String title) {
    return InkWell(
      onTap: () => setState(() => _selected = title),
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

            if (_selected == title)
              const Icon(Icons.check_circle, color: AppColors.success)
            else
              const Icon(Icons.download, color: AppColors.textSecondary),
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