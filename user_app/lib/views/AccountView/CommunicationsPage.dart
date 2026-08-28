import 'package:flutter/material.dart';

import 'CommunicationTogglePage.dart';
import 'SurgeNotificationPage.dart';
import 'package:ravelgo_user_app/theme/app_theme.dart';

class CommunicationsPage extends StatelessWidget {
  const CommunicationsPage({super.key});

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
                    "Communications",
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

                    /// CARD
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          _tile("Surge hour Notifications",context),
                          _divider(),
                          _tile("Promotions",context),
                          _divider(),
                          _tile("Ravel Go’s offers",context),
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

  /// TILE
  Widget _tile(String title,BuildContext context) {
    return InkWell(
      onTap: () {
        if (title == "Surge hour Notifications") {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => SurgeNotificationPage()),
          );
        } else if (title == "Promotions") {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const CommunicationTogglePage(
                title: "Promotions",
              ),
            ),
          );
        } else if (title == "Ravel Go’s offers") {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const CommunicationTogglePage(
                title: "Ravel Go’s offers",
              ),
            ),
          );

        }
      },
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