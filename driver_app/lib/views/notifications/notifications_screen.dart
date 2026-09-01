import 'package:flutter/material.dart';
import 'package:ravelgo_driver_app/theme/app_theme.dart';

/// Driver notification center.
/// BACKEND BOUNDARY: no notification service is connected, so this shows an
/// honest empty state rather than fabricated notifications. When the push /
/// notification feed exists, its items render in place of the empty state.
class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Notifications')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Icon(Icons.notifications_none, size: 64, color: AppColors.textMuted),
              SizedBox(height: 16),
              Text('No notifications yet',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              SizedBox(height: 8),
              Text(
                'Ride requests, payout updates and incentives will appear here once notifications are enabled for your account.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
