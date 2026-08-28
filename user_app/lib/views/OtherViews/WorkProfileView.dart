import 'package:flutter/material.dart';
import 'package:ravelgo_user_app/theme/app_theme.dart';

class WorkProfileView extends StatelessWidget {
  const WorkProfileView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(70),
        child: Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.only(
              bottomLeft: Radius.circular(24),
              bottomRight: Radius.circular(24),
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: const [
                  BackButton(color: AppColors.textPrimary),
                  Spacer(),
                  Text(
                    'Work Profile',
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
      body:Container(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child:
              ListView(
                children: const [
                  _SettingsTile(
                    icon: Icons.work_outline,
                    title: 'Add company details',
                    showValue: false,
                  ),
                  Divider(height: 1),

                  _SettingsTile(
                    icon: Icons.email_outlined,
                    title: 'Work email',
                    value: 'thelmaibeh2@gmail.com',
                  ),
                  Divider(height: 1),

                  _SettingsTile(
                    icon: Icons.account_balance_wallet_outlined,
                    title: 'Payment method',
                    value: 'Cash',
                    valueColor: AppColors.textPrimary,
                    iconColor: Colors.brown,
                  ),
                  Divider(height: 1),
                ],
              ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? value;
  final bool showValue;
  final Color? iconColor;
  final Color? valueColor;

  const _SettingsTile({
    required this.icon,
    required this.title,
    this.value,
    this.showValue = true,
    this.iconColor,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Icon(icon, color: iconColor ?? AppColors.textSecondary),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: (showValue && value != null) ? [
          Text(
            title,
            style: const TextStyle(color: AppColors.textMuted, fontSize: 14),
          ),
            Text(
              value!,
              style: TextStyle(
                color: valueColor ?? AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),

        ]:[ Text(
              title,
          style: const  TextStyle(
            color:  AppColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w500,
          ),
        ),],
      ),
      trailing: const Icon(Icons.chevron_right, color: AppColors.textMuted),
      onTap: () {
        print('Tapped on $title');
      },
    );
  }
}