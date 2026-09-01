import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ravelgo_user_app/theme/app_theme.dart';

/// Rider safety toolkit (opened from Home's shield button).
/// Each action has defined behavior: emergency numbers copy to the clipboard
/// (no dialer plugin is configured in this build - stated in the UI), and
/// live features that need the trips backend say so instead of dead-ending.
class SafetyScreen extends StatelessWidget {
  const SafetyScreen({super.key});

  void _copyNumber(BuildContext context, String label, String number) {
    Clipboard.setData(ClipboardData(text: number));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label ($number) copied - paste it in your phone app to call')),
    );
  }

  void _notAvailable(BuildContext context, String what) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$what requires an active trip and the trips service - not available in this build')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Safety')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Emergency', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                const Text('Nigeria emergency lines',
                    style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.sos, color: AppColors.error),
                  title: const Text('Emergency services'),
                  subtitle: const Text('112'),
                  trailing: const Icon(Icons.copy, size: 18, color: AppColors.textMuted),
                  onTap: () => _copyNumber(context, 'Emergency services', '112'),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.local_police_outlined, color: AppColors.error),
                  title: const Text('Police'),
                  subtitle: const Text('199'),
                  trailing: const Icon(Icons.copy, size: 18, color: AppColors.textMuted),
                  onTap: () => _copyNumber(context, 'Police', '199'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.share_location_outlined, color: AppColors.textSecondary),
                  title: const Text('Share live trip'),
                  subtitle: const Text('Let trusted contacts follow your ride'),
                  trailing: const Icon(Icons.chevron_right, size: 18, color: AppColors.textMuted),
                  onTap: () => _notAvailable(context, 'Live trip sharing'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.report_outlined, color: AppColors.textSecondary),
                  title: const Text('Report a safety issue'),
                  subtitle: const Text('Tell us about a trip or driver concern'),
                  trailing: const Icon(Icons.chevron_right, size: 18, color: AppColors.textMuted),
                  onTap: () => showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Report a safety issue'),
                      content: const Text(
                          'For urgent issues call 112. For anything else, contact support from '
                          'Account > Contact support and our safety team will follow up.'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
