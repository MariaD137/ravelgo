import 'package:flutter/material.dart';
import 'package:ravelgo_user_app/theme/app_theme.dart';
import 'package:ravelgo_user_app/views/RideView/RidesView.dart';

class SupportView extends StatelessWidget {
  const SupportView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(70),
        child: Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.only(
              bottomLeft: Radius.circular(24),
              bottomRight: Radius.circular(24),
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.border,
                blurRadius: 4,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: const [
                  BackButton(color: AppColors.textPrimary),
                  Spacer(),
                  Text(
                    'Payment',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.normal, color: AppColors.textPrimary),
                  ),
                  Spacer(),
                  SizedBox(width: 64)
                ],
              ),
            ),
          ),
        ),
      ),
      backgroundColor: AppColors.surface,
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          const Text(
            'Do you need help with  trips?',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 12),

          // Recent trips header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            color: AppColors.surfaceElevated,
            child: const Text('Your Recent trips'),
          ),

          // Trip items
          ...List.generate(3, (index) {
            return ListTile(
              dense: true,
              title: const Text("Yesterday, 18:45"),
              trailing: const Text("#1500", style: TextStyle(color: AppColors.textMuted)),
              onTap: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => RidesView()));
              },
              contentPadding: EdgeInsets.zero,
            );
          }),

          // View all trips
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => RidesView()));
              },
              child: const Text(
                "View all trips",
                style: TextStyle(color: AppColors.success),
              ),
            ),
          ),

          const SizedBox(height: 16),
          const Text(
            'Do you need help with something else?',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 12),

          // Help Categories
          _helpCategoryTile(context, 'Get help with something else'),
          _helpCategoryTile(context, 'About  Ravel Go'),
          _helpCategoryTile(context, 'Ride booking issues'),
          _helpCategoryTile(context, 'Pricing and payments'),
          _helpCategoryTile(context, 'Ride experience & safety'),
          _helpCategoryTile(context, 'Lost & Found'),
          _helpCategoryTile(context, 'App and account issue'),
        ],
      ),
    );
  }

  Widget _helpCategoryTile(BuildContext context, String label) {
    return Column(
      children: [
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 0),
          title: Text(label),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            // Help-center articles are not published yet; tell the user how
            // to get help instead of dead-ending.
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: Text(label),
                content: const Text(
                    'Help articles for this topic are coming soon. For now, reach us '
                    'through "Do you need help with something else?" below and our team '
                    'will assist you.'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
                ],
              ),
            );
          },
        ),
        const Divider(height: 1),
      ],
    );
  }
}