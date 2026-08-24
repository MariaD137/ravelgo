import 'package:flutter/material.dart';

class WorkProfileView extends StatelessWidget {
  const WorkProfileView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(70),
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
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
                  BackButton(color: Colors.black),
                  Spacer(),
                  Text(
                    'Work Profile',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.normal, color: Colors.black),
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
                    valueColor: Colors.black,
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
      leading: Icon(icon, color: iconColor ?? Colors.grey[700]),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: (showValue && value != null) ? [
          Text(
            title,
            style: const TextStyle(color: Colors.grey, fontSize: 14),
          ),
            Text(
              value!,
              style: TextStyle(
                color: valueColor ?? Colors.black,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),

        ]:[ Text(
              title,
          style: const  TextStyle(
            color:  Colors.black,
            fontSize: 18,
            fontWeight: FontWeight.w500,
          ),
        ),],
      ),
      trailing: const Icon(Icons.chevron_right, color: Colors.grey),
      onTap: () {
      },
    );
  }
}